export interface ArchiveInfo {
  count: number;
  bytes: number;
  encrypted: boolean;
}
declare const archive: {
  inspect(path: string): ArchiveInfo;
  extract(path: string, destination: string, password: string): Promise<ArchiveInfo>;
};
export default archive;
