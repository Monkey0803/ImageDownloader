import { image } from '@kit.ImageKit';

export class GalleryCoverInfo {
  width: number = 0;
  height: number = 0;
  hdr: boolean = false;

  static async read(path: string): Promise<GalleryCoverInfo> {
    const result: GalleryCoverInfo = new GalleryCoverInfo();
    if (path.length === 0) { return result; }
    let source: image.ImageSource | undefined = undefined;
    try {
      source = image.createImageSource(path);
      const info: image.ImageInfo = await source.getImageInfo();
      result.hdr = info.isHdr === true;
      let orientation: number = 1;
      try {
        const value: string = await source.getImageProperty(image.PropertyKey.ORIENTATION);
        const named: number = ['Top-left', 'Top-right', 'Bottom-right', 'Bottom-left',
          'Left-top', 'Right-top', 'Right-bottom', 'Left-bottom'].indexOf(value);
        orientation = named >= 0 ? named + 1 : Number(value);
      } catch (error) {}
      const swapped: boolean = orientation >= 5 && orientation <= 8;
      result.width = swapped ? info.size.height : info.size.width;
      result.height = swapped ? info.size.width : info.size.height;
      if (result.width <= 0 || result.height <= 0) { result.width = 0; result.height = 0; }
    } catch (error) {}
    finally { if (source !== undefined) { try { await source.release(); } catch (error) {} } }
    return result;
  }
}
