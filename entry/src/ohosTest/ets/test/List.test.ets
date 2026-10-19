import downloadStoreTest from './DownloadStore.test';
import mediaFormatTest from './MediaFormat.test';
import imageCandidatesTest from './ImageCandidates.test';

export default function testsuite() {
  downloadStoreTest();
  mediaFormatTest();
  imageCandidatesTest();
}
