import { describe, it, expect } from '@ohos/hypium';
import { BrowserCollection, BrowserData, BrowserEntry } from '../../../main/ets/service/BrowserCollection';

export default function browserCollectionTest() {
  describe('BrowserCollection', () => {
    it('moves_revisited_page_to_front_and_caps_history', 0, () => {
      let entries: BrowserEntry[] = [];
      entries = BrowserCollection.remember(entries, 'https://example.org/a', 'A', 1, 2);
      entries = BrowserCollection.remember(entries, 'https://example.org/b', 'B', 2, 2);
      entries = BrowserCollection.remember(entries, 'https://example.org/a', 'A new', 3, 2);
      expect(entries.length).assertEqual(2);
      expect(entries[0].title).assertEqual('A new');
      expect(entries[1].url).assertEqual('https://example.org/b');
      entries = BrowserCollection.remember(entries, 'https://example.org/c', '', 4, 2);
      expect(entries[1].url).assertEqual('https://example.org/a');
    });

    it('rejects_non_web_urls_and_sanitizes_saved_data', 0, () => {
      const data: BrowserData = new BrowserData();
      data.history = BrowserCollection.remember([], 'about:blank', 'Blank', 1, 100);
      expect(data.history.length).assertEqual(0);
      const bad: BrowserEntry = new BrowserEntry();
      bad.url = 'javascript:alert(1)';
      bad.title = 'Bad';
      data.bookmarks = [bad];
      expect(BrowserCollection.normalize(data).bookmarks.length).assertEqual(0);
    });
  });
}
