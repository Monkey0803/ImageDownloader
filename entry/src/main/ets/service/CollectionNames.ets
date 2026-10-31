import { PictureItem } from '../model/Models';
import { Naming } from './Naming';

/** Stable page identity and safe on-disk names for new collection batches. */
export class CollectionNames {
  static id(pageUrl: string, session: string): string {
    return pageUrl.length > 0 ? 'page:' + pageUrl : 'direct:' + session;
  }

  static label(title: string): string {
    return Naming.clean(title, '网页素材').substring(0, 64);
  }

  static folder(title: string, id: string): string {
    let hash: number = 2166136261;
    for (let index: number = 0; index < id.length; index++) {
      hash = Math.imul(hash ^ id.charCodeAt(index), 16777619) >>> 0;
    }
    return CollectionNames.label(title) + '-' + hash.toString(16).padStart(8, '0');
  }

  static filename(picture: PictureItem, title: string, index: number, mode: string): string {
    const suggested: string = Naming.suggested(picture.url, picture.description, index);
    const extension: string = suggested.substring(suggested.lastIndexOf('.') + 1);
    if (mode === 'numbered') {
      const stem: string = CollectionNames.label(title).substring(0, 100);
      return Naming.clean(stem + '_' + index.toString().padStart(3, '0') + '.' + extension, suggested);
    }
    return picture.userNamed ? Naming.withExtension(picture.name, extension) : Naming.clean(picture.name, suggested);
  }
}
