#include <napi/native_api.h>
#include <zip.h>
#include <algorithm>
#include <array>
#include <cstdint>
#include <filesystem>
#include <fcntl.h>
#include <set>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

namespace {
namespace fs = std::filesystem;
constexpr zip_uint64_t kMaxEntries = 5000;
constexpr zip_uint64_t kMaxBytes = 1024ULL * 1024ULL * 1024ULL;

struct ArchiveInfo { uint64_t count = 0; uint64_t bytes = 0; bool encrypted = false; };
struct Work {
    napi_async_work handle = nullptr;
    napi_deferred deferred = nullptr;
    std::string source, destination, password, error;
    ArchiveInfo info;
};

std::string String(napi_env env, napi_value value) {
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok || length > 65536) return {};
    std::string result(length + 1, '\0');
    if (length > 0) napi_get_value_string_utf8(env, value, result.data(), result.size(), &length);
    result.resize(length);
    return result;
}

bool SafeName(const std::string &name, bool directory) {
    if (name.empty() || name.size() > 1024 || name[0] == '/' || name.find('\\') != std::string::npos ||
        name.find(':') != std::string::npos || name.find('\0') != std::string::npos) return false;
    if (directory != (name.back() == '/')) return false;
    fs::path path(name);
    unsigned depth = 0;
    for (const auto &part : path) {
        if (++depth > 32) return false;
        auto text = part.string();
        if (text == "." || text == ".." || text.empty()) return false;
        for (unsigned char ch : text) if (ch < 32) return false;
    }
    return true;
}

bool Inspect(zip_t *archive, ArchiveInfo &result, std::string &error) {
    const zip_int64_t count = zip_get_num_entries(archive, 0);
    if (count < 0 || static_cast<uint64_t>(count) > kMaxEntries) { error = "文件数量超出限制"; return false; }
    std::set<std::string> names;
    for (zip_uint64_t i = 0; i < static_cast<zip_uint64_t>(count); ++i) {
        zip_stat_t stat; zip_stat_init(&stat);
        if (zip_stat_index(archive, i, 0, &stat) != 0 || !stat.name) { error = "压缩包目录损坏"; return false; }
        const std::string name(stat.name);
        const bool directory = !name.empty() && name.back() == '/';
        if (!SafeName(name, directory) || !names.insert(name).second) { error = "压缩包包含不安全或重复路径"; return false; }
        zip_uint8_t opsys = 0; zip_uint32_t attributes = 0;
        if (zip_file_get_external_attributes(archive, i, 0, &opsys, &attributes) == 0 && opsys == ZIP_OPSYS_UNIX) {
            const mode_t mode = static_cast<mode_t>(attributes >> 16);
            if ((mode & S_IFMT) != 0 && !(directory ? S_ISDIR(mode) : S_ISREG(mode))) {
                error = "压缩包包含链接或特殊文件"; return false;
            }
        }
        if (!directory) {
            if (!zip_compression_method_supported(stat.comp_method, 0)) {
                error = "不支持的 ZIP 压缩方法"; return false;
            }
            if (!zip_encryption_method_supported(stat.encryption_method, 0)) {
                error = "不支持的 ZIP 加密格式"; return false;
            }
            if (!(stat.valid & ZIP_STAT_SIZE) || stat.size > kMaxBytes - result.bytes) {
                error = "解压大小超出限制"; return false;
            }
            result.bytes += stat.size;
            result.count++;
        }
        if ((stat.valid & ZIP_STAT_ENCRYPTION_METHOD) && stat.encryption_method != ZIP_EM_NONE)
            result.encrypted = true;
    }
    return true;
}

zip_t *Open(const std::string &path, std::string &error) {
    int code = 0;
    zip_t *archive = zip_open(path.c_str(), ZIP_RDONLY, &code);
    if (!archive) error = "无法打开 ZIP：文件可能已损坏";
    return archive;
}

bool Extract(Work &work) {
    zip_t *archive = Open(work.source, work.error);
    if (!archive) return false;
    if (!Inspect(archive, work.info, work.error)) { zip_close(archive); return false; }
    std::error_code ec;
    if (fs::exists(work.destination, ec) || !fs::create_directories(work.destination, ec) || ec) {
        work.error = "临时目录不可用"; zip_close(archive); return false;
    }
    uint64_t written = 0;
    const zip_int64_t count = zip_get_num_entries(archive, 0);
    for (zip_uint64_t i = 0; i < static_cast<zip_uint64_t>(count); ++i) {
        zip_stat_t stat; zip_stat_init(&stat);
        if (zip_stat_index(archive, i, 0, &stat) != 0) { work.error = "压缩包目录损坏"; break; }
        const std::string name(stat.name);
        const fs::path target = fs::path(work.destination) / name;
        if (name.back() == '/') { fs::create_directories(target, ec); if (ec) { work.error = "创建目录失败"; break; } continue; }
        fs::create_directories(target.parent_path(), ec);
        if (ec) { work.error = "创建目录失败"; break; }
        zip_file_t *input = stat.encryption_method == ZIP_EM_NONE
            ? zip_fopen_index(archive, i, 0)
            : zip_fopen_index_encrypted(archive, i, 0, work.password.c_str());
        if (!input) { work.error = stat.encryption_method == ZIP_EM_NONE ? "无法读取压缩文件" : "密码错误或不支持的加密格式"; break; }
        const int output = open(target.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
        if (output < 0) { zip_fclose(input); work.error = "创建解压文件失败"; break; }
        std::array<char, 65536> buffer;
        uint64_t entryWritten = 0;
        while (true) {
            const zip_int64_t size = zip_fread(input, buffer.data(), buffer.size());
            if (size < 0) { work.error = "密码错误或压缩数据损坏"; break; }
            if (size == 0) break;
            if (static_cast<uint64_t>(size) > kMaxBytes - written ||
                static_cast<uint64_t>(size) > stat.size - entryWritten) { work.error = "实际解压大小超出限制"; break; }
            const char *cursor = buffer.data(); ssize_t remaining = size;
            while (remaining > 0) {
                const ssize_t n = write(output, cursor, remaining);
                if (n <= 0) { work.error = "写入解压文件失败"; break; }
                cursor += n; remaining -= n;
            }
            if (!work.error.empty()) break;
            written += size; entryWritten += size;
        }
        close(output);
        const int closed = zip_fclose(input);
        if (closed != 0 && work.error.empty()) work.error = "压缩文件校验失败";
        if (entryWritten != stat.size && work.error.empty()) work.error = "解压文件大小不符";
        if (!work.error.empty()) break;
    }
    zip_close(archive);
    if (!work.error.empty()) fs::remove_all(work.destination, ec);
    return work.error.empty();
}

napi_value InfoValue(napi_env env, const ArchiveInfo &info) {
    napi_value value, field; napi_create_object(env, &value);
    napi_create_double(env, static_cast<double>(info.count), &field); napi_set_named_property(env, value, "count", field);
    napi_create_double(env, static_cast<double>(info.bytes), &field); napi_set_named_property(env, value, "bytes", field);
    napi_get_boolean(env, info.encrypted, &field); napi_set_named_property(env, value, "encrypted", field);
    return value;
}

napi_value InspectCall(napi_env env, napi_callback_info call) {
    size_t argc = 1; napi_value args[1]; napi_get_cb_info(env, call, &argc, args, nullptr, nullptr);
    if (argc != 1) { napi_throw_type_error(env, nullptr, "inspect(path) requires a path"); return nullptr; }
    std::string error; zip_t *archive = Open(String(env, args[0]), error);
    if (!archive) { napi_throw_error(env, nullptr, error.c_str()); return nullptr; }
    ArchiveInfo info; Inspect(archive, info, error); zip_close(archive);
    if (!error.empty()) { napi_throw_error(env, nullptr, error.c_str()); return nullptr; }
    return InfoValue(env, info);
}

void Execute(napi_env, void *data) { Extract(*static_cast<Work *>(data)); }
void Complete(napi_env env, napi_status status, void *data) {
    auto *work = static_cast<Work *>(data); napi_value result;
    if (status == napi_ok && work->error.empty()) {
        result = InfoValue(env, work->info); napi_resolve_deferred(env, work->deferred, result);
    } else {
        napi_create_string_utf8(env, work->error.c_str(), NAPI_AUTO_LENGTH, &result);
        napi_reject_deferred(env, work->deferred, result);
    }
    napi_delete_async_work(env, work->handle); delete work;
}
napi_value ExtractCall(napi_env env, napi_callback_info call) {
    size_t argc = 3; napi_value args[3]; napi_get_cb_info(env, call, &argc, args, nullptr, nullptr);
    if (argc != 3) { napi_throw_type_error(env, nullptr, "extract(path, directory, password) requires three arguments"); return nullptr; }
    auto *work = new Work{};
    work->source = String(env, args[0]); work->destination = String(env, args[1]); work->password = String(env, args[2]);
    napi_value promise, name; napi_create_promise(env, &work->deferred, &promise);
    napi_create_string_utf8(env, "extractZip", NAPI_AUTO_LENGTH, &name);
    napi_create_async_work(env, nullptr, name, Execute, Complete, work, &work->handle);
    napi_queue_async_work(env, work->handle);
    return promise;
}
napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor properties[] = {
        {"inspect", nullptr, InspectCall, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"extract", nullptr, ExtractCall, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, 2, properties); return exports;
}
}
static napi_module module = {1, 0, nullptr, Init, "archiveextract", nullptr, {0}};
extern "C" __attribute__((constructor)) void Register() { napi_module_register(&module); }
