import downloadStoreTest from './DownloadStore.test';
import mediaFormatTest from './MediaFormat.test';
import imageCandidatesTest from './ImageCandidates.test';
import pictureFiltersTest from './PictureFilters.test';
import pictureFactoryTest from './PictureFactory.test';
import weiboLivePhotosTest from './WeiboLivePhotos.test';
import libraryQueryTest from './LibraryQuery.test';
import shareInboxTest from './ShareInbox.test';
import sizeArbiterTest from './SizeArbiter.test';
import browserCollectionTest from './BrowserCollection.test';
import duplicateFinderTest from './DuplicateFinder.test';
import tasksViewModelTest from './TasksViewModel.test';
import batchLinksTest from './BatchLinks.test';
import batchPagesTest from './BatchPages.test';
import batchPagesUiTest from './BatchPagesUi.test';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import widgetSnapshotTest from './WidgetSnapshot.test';
import galleryBatchingTest from './GalleryBatching.test';
import pageExpansionTest from './PageExpansion.test';
import saveReceiptTest from './SaveReceipt.test';
import batchViewTest from './BatchView.test';
import libraryCatalogTest from './LibraryCatalog.test';

import libraryVisionTest from './LibraryVision.test';
import imageEditTest from './ImageEdit.test';
import editRegistrationTest from './EditRegistration.test';
import libraryFixturesTest from './LibraryFixtures.test';
import zipArchiveTest from './ZipArchive.test';
import hdrDecodeTest from './HdrDecode.test';
import livePhotoTest from './LivePhoto.test';
import superResolutionTest from './SuperResolution.test';
import collectionGroupsTest from './CollectionGroups.test';

export default function testsuite() {
  if (abilityDelegatorRegistry.getArguments().parameters['-s batchPagesUi'] === 'true') {
    batchPagesUiTest();
    return;
  }
  downloadStoreTest();
  mediaFormatTest();
  imageCandidatesTest();
  pictureFiltersTest();
  pictureFactoryTest();
  weiboLivePhotosTest();
  libraryQueryTest();
  shareInboxTest();
  sizeArbiterTest();
  browserCollectionTest();
  duplicateFinderTest();
  tasksViewModelTest();
  batchLinksTest();
  batchPagesTest();
  widgetSnapshotTest();
  galleryBatchingTest();
  pageExpansionTest();
  saveReceiptTest();
  batchViewTest();
  libraryCatalogTest();
  libraryVisionTest();
  imageEditTest();
  editRegistrationTest();
  libraryFixturesTest();
  zipArchiveTest();
  hdrDecodeTest();
  livePhotoTest();
  superResolutionTest();
  collectionGroupsTest();
}
