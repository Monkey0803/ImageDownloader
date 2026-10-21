import downloadStoreTest from './DownloadStore.test';
import mediaFormatTest from './MediaFormat.test';
import imageCandidatesTest from './ImageCandidates.test';
import pictureFiltersTest from './PictureFilters.test';
import libraryQueryTest from './LibraryQuery.test';
import shareInboxTest from './ShareInbox.test';
import sizeArbiterTest from './SizeArbiter.test';
import browserCollectionTest from './BrowserCollection.test';
import duplicateFinderTest from './DuplicateFinder.test';
import tasksViewModelTest from './TasksViewModel.test';
import batchLinksTest from './BatchLinks.test';

export default function testsuite() {
  downloadStoreTest();
  mediaFormatTest();
  imageCandidatesTest();
  pictureFiltersTest();
  libraryQueryTest();
  shareInboxTest();
  sizeArbiterTest();
  browserCollectionTest();
  duplicateFinderTest();
  tasksViewModelTest();
  batchLinksTest();
}
