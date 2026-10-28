import { describe, it, expect } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs, hash } from '@kit.CoreFileKit';
import { DownloadItem, SavedState } from '../../../main/ets/model/Models';
import { EditResult, EditTicket } from '../../../main/ets/model/ImageEditDocument';
import { EditJournal } from '../../../main/ets/service/EditJournal';
import { DownloadStore } from '../../../main/ets/service/DownloadStore';
import { StoreState } from '../../../main/ets/service/StoreState';
import { LIBRARY_CATALOG } from '../../../main/ets/service/LibraryCatalog';
import { TasksViewModel } from '../../../main/ets/viewmodel/TasksViewModel';

// Run this suite in a fresh, dedicated native-test process, then force-stop it before launching UI.
// LIBRARY_CATALOG is deliberately initialized only here (last suite), and has no reset API.
// registerEdited only needs filesDir; never initialize the production store or native download agent.
class IsolatedFilesContext {
  filesDir: string;
  constructor(path: string) { this.filesDir = path; }
}

function write(path: string, text: string): void {
  const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
  try { fs.writeSync(file.fd, text); } finally { fs.closeSync(file); }
}

function cleanupOwnedFolder(path: string): void {
  if (!fs.accessSync(path)) { return; }
  for (const name of fs.listFileSync(path)) {
    const child: string = path + '/' + name;
    if (fs.statSync(child).isDirectory()) { cleanupOwnedFolder(child); } else { fs.unlinkSync(child); }
  }
  fs.rmdirSync(path);
}

function folder(name: string): string {
  const value: string = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().filesDir +
    '/library-test-' + name + '-' + Date.now().toString();
  fs.mkdirSync(value, true); return value;
}

function resultFor(ticket: EditTicket): EditResult {
  const result: EditResult = new EditResult();
  result.path = ticket.pendingPath; result.bytes = fs.statSync(ticket.pendingPath).size;
  result.width = 2; result.height = 2; return result;
}

async function finalized(root: string, id: string, sourceId: string): Promise<EditTicket> {
  const ticket: EditTicket = await EditJournal.prepare(root, id, sourceId);
  write(ticket.pendingPath, 'isolated-edited-file-' + id);
  await EditJournal.finalize(ticket, resultFor(ticket));
  return ticket;
}

function finalizedResult(ticket: EditTicket): EditResult {
  const result: EditResult = new EditResult(); result.path = ticket.pendingPath;
  result.bytes = fs.statSync(ticket.finalPath).size; result.width = 2; result.height = 2;
  return result;
}

export default function editRegistrationTest() {
  describe('EditRegistrationNative', () => {
    it('finalizes_and_rolls_back_only_owned_journal_paths', 0, async () => {
      const root: string = folder('journal');
      try {
        const ticket: EditTicket = await EditJournal.prepare(root, 'copy', 'source');
        expect(fs.accessSync(ticket.journalPath)).assertTrue();
        expect(fs.accessSync(ticket.journalPath + '.tmp')).assertFalse();
        write(ticket.pendingPath, 'PNG-probe-bytes');
        const result: EditResult = resultFor(ticket);
        let duplicateRejected: boolean = false;
        try { await EditJournal.prepare(root, 'copy', 'source'); } catch (error) { duplicateRejected = true; }
        expect(duplicateRejected).assertTrue();
        await EditJournal.finalize(ticket, result);
        expect(fs.accessSync(ticket.pendingPath)).assertFalse();
        expect(fs.readTextSync(ticket.finalPath)).assertEqual('PNG-probe-bytes');
        expect(fs.accessSync(ticket.journalPath)).assertTrue();
        await EditJournal.rollback(ticket);
        expect(fs.accessSync(ticket.finalPath)).assertFalse();
        expect(fs.accessSync(ticket.journalPath)).assertFalse();
        await EditJournal.rollback(ticket);
        const kept: EditTicket = await finalized(root, 'kept', 'source');
        await EditJournal.finish(kept);
        expect(fs.accessSync(kept.journalPath)).assertFalse();
        await EditJournal.rollback(kept);
        expect(fs.accessSync(kept.finalPath)).assertTrue();
      } finally { cleanupOwnedFolder(root); }
    });

    it('recovers_unregistered_outputs_but_preserves_registered_and_untrusted_paths', 0, async () => {
      const root: string = folder('recovery');
      try {
        const pending: EditTicket = await EditJournal.prepare(root, 'pending', 'source');
        write(pending.pendingPath, 'incomplete');
        const orphan: EditTicket = await finalized(root, 'orphan', 'source');
        const kept: EditTicket = await finalized(root, 'registered', 'source');
        const registered: DownloadItem = new DownloadItem();
        registered.id = kept.id; registered.origin = 'edited'; registered.path = kept.finalPath;
        const external: string = root + '/outside-edits.txt'; write(external, 'must-stay');
        const forged: EditTicket = new EditTicket();
        forged.id = 'forged'; forged.originalId = 'source';
        forged.journalPath = root + '/edits/edit-forged.json';
        forged.pendingPath = external; forged.finalPath = external;
        write(forged.journalPath, JSON.stringify(forged));
        write(root + '/edits/edit-bad.json', '{broken');
        await EditJournal.recover(root, [registered]);
        expect(fs.accessSync(pending.pendingPath)).assertFalse();
        expect(fs.accessSync(pending.journalPath)).assertFalse();
        expect(fs.accessSync(orphan.finalPath)).assertFalse();
        expect(fs.accessSync(orphan.journalPath)).assertFalse();
        expect(fs.accessSync(kept.finalPath)).assertTrue();
        expect(fs.accessSync(kept.journalPath)).assertFalse();
        expect(fs.readTextSync(external)).assertEqual('must-stay');
        expect(fs.accessSync(forged.journalPath)).assertTrue();
        expect(fs.readTextSync(root + '/edits/edit-bad.json')).assertEqual('{broken');
      } finally { cleanupOwnedFolder(root); }
    });

    it('excludes_edited_copies_from_task_lists_and_running_counts', 0, () => {
      const downloads: DownloadItem[] = DownloadStore.downloads;
      const batches = DownloadStore.batches;
      try {
        const original: DownloadItem = new DownloadItem(); original.id = 'source'; original.status = 'completed';
        const edit: DownloadItem = new DownloadItem(); edit.id = 'copy'; edit.origin = 'edited'; edit.status = 'completed';
        const editedActive: DownloadItem = new DownloadItem();
        editedActive.id = 'copy-active'; editedActive.origin = 'edited'; editedActive.status = 'running';
        DownloadStore.downloads = [edit, original, editedActive]; DownloadStore.batches = [];
        const model: TasksViewModel = new TasksViewModel(); model.sync();
        expect(model.downloads.length).assertEqual(1); expect(model.settled[0].id).assertEqual('source');
        expect(model.active.length).assertEqual(0); expect(model.running).assertEqual(0);
        DownloadStore.downloads = [edit]; model.sync(); expect(model.isEmpty()).assertTrue();
        expect(DownloadStore.downloads.length).assertEqual(1);
      } finally { DownloadStore.downloads = downloads; DownloadStore.batches = batches; }
    });

    it('durably_registers_in_isolation_inherits_tags_and_rolls_back_failed_state_write', 0, async () => {
      const root: string = folder('registration');
      const oldContext: common.UIAbilityContext = DownloadStore.context;
      const oldDownloads: DownloadItem[] = DownloadStore.downloads;
      const oldListeners: (() => void)[] = DownloadStore.listeners;
      const oldProblem: string = DownloadStore.saveProblem;
      const registrations: Promise<DownloadItem>[] = [];
      try {
        DownloadStore.context = new IsolatedFilesContext(root) as common.UIAbilityContext;
        DownloadStore.listeners = [];
        const source: DownloadItem = new DownloadItem();
        source.id = 'original'; source.path = root + '/source.png'; source.name = 'Original.png';
        source.sourcePage = 'https://isolated.example/source'; source.status = 'completed';
        write(source.path, 'unchanged-original');
        const originalHash: string = await hash.hash(source.path, 'sha256');
        DownloadStore.downloads = [source];
        await LIBRARY_CATALOG.initialize(root); await LIBRARY_CATALOG.reconcile([source]);
        await LIBRARY_CATALOG.changeTags([source.id], ['QA标签'], []);
        await LIBRARY_CATALOG.setFavorite([source.id], true);
        const ticket: EditTicket = await finalized(root, 'copy', source.id);
        const result: EditResult = finalizedResult(ticket);
        registrations.push(DownloadStore.registerEdited(source.id, ticket, result));
        registrations.push(DownloadStore.registerEdited(source.id, ticket, result));
        const registered: DownloadItem[] = await Promise.all(registrations);
        expect(registered[0].id).assertEqual(ticket.id); expect(registered[1].id).assertEqual(ticket.id);
        expect(DownloadStore.downloads.length).assertEqual(2);
        expect(registered[0].origin).assertEqual('edited'); expect(registered[0].originalId).assertEqual(source.id);
        expect(registered[0].url).assertEqual(''); expect(registered[0].batchId).assertEqual('');
        expect(registered[0].taskId).assertEqual(''); expect(registered[0].sourcePage).assertEqual(source.sourcePage);
        expect(LIBRARY_CATALOG.getMeta(ticket.id).tags.join(',')).assertEqual('QA标签');
        expect(LIBRARY_CATALOG.getMeta(ticket.id).favorite).assertFalse();
        expect(fs.accessSync(ticket.finalPath)).assertTrue(); expect(fs.accessSync(ticket.journalPath)).assertFalse();
        const parsed: SavedState | undefined = StoreState.parse(fs.readTextSync(root + '/download-state.json'));
        expect(parsed !== undefined).assertTrue();
        if (parsed !== undefined) {
          expect(parsed.downloads.length).assertEqual(2);
          expect(parsed.downloads[0].origin).assertEqual('edited');
          expect(parsed.downloads[0].originalId).assertEqual(source.id);
        }
        const first: EditTicket = await finalized(root, 'parallel-a', source.id);
        const second: EditTicket = await finalized(root, 'parallel-b', source.id);
        registrations.push(DownloadStore.registerEdited(source.id, first, finalizedResult(first)));
        registrations.push(DownloadStore.registerEdited(source.id, second, finalizedResult(second)));
        await Promise.all(registrations);
        expect(DownloadStore.downloads.length).assertEqual(4);
        const statePath: string = root + '/download-state.json';
        const stateHash: string = await hash.hash(statePath, 'sha256');
        fs.renameSync(statePath, statePath + '.backup'); fs.mkdirSync(statePath);
        const failed: EditTicket = await finalized(root, 'write-fails', source.id);
        let rejected: boolean = false;
        try { await DownloadStore.registerEdited(source.id, failed, finalizedResult(failed)); }
        catch (error) { rejected = true; }
        expect(rejected).assertTrue(); expect(DownloadStore.downloads.length).assertEqual(4);
        expect(fs.accessSync(failed.finalPath)).assertFalse(); expect(fs.accessSync(failed.journalPath)).assertFalse();
        expect(LIBRARY_CATALOG.getMeta(failed.id).tags.length).assertEqual(0);
        fs.rmdirSync(statePath); fs.renameSync(statePath + '.backup', statePath);
        expect(await hash.hash(statePath, 'sha256')).assertEqual(stateHash);
        expect(await hash.hash(source.path, 'sha256')).assertEqual(originalHash);
        const tasks: TasksViewModel = new TasksViewModel(); tasks.sync();
        expect(tasks.downloads.length).assertEqual(1); expect(tasks.settled[0].id).assertEqual(source.id);
      } finally {
        // Promise.all is fail-fast; drain every queued registration before restoring any static context.
        await Promise.all(registrations.map((task: Promise<DownloadItem>): Promise<void> =>
          task.then((): void => {}, (): void => {})));
        DownloadStore.context = oldContext; DownloadStore.downloads = oldDownloads;
        DownloadStore.listeners = oldListeners; DownloadStore.saveProblem = oldProblem;
        try { await LIBRARY_CATALOG.reconcile([]); } finally { cleanupOwnedFolder(root); }
      }
    });
  });
}
