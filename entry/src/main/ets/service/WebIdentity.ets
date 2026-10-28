import { webview } from '@kit.ArkWeb';

/**
 * Request identity shared by downloads, previews and HEAD probes.
 *
 * Some image CDNs (Coolapk's `image.coolapk.com` is one) answer non-browser clients with an
 * HTML anti-bot challenge (HTTP 567) instead of the image. Sending the same User-Agent the
 * embedded browser uses keeps those requests on the normal image path. The value is cached
 * for the process; the constant is only a fallback for devices without the Web capability.
 */
export class WebIdentity {
  static readonly FALLBACK_USER_AGENT: string =
    'Mozilla/5.0 (Phone; OpenHarmony 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 ArkWeb/4.1.6.1 Mobile';
  private static cachedUserAgent: string = '';

  static userAgent(): string {
    if (WebIdentity.cachedUserAgent.length > 0) {
      return WebIdentity.cachedUserAgent;
    }
    try {
      const agent: string = webview.WebviewController.getDefaultUserAgent();
      if (agent.length > 0) {
        WebIdentity.cachedUserAgent = agent;
        return agent;
      }
    } catch (error) {}
    WebIdentity.cachedUserAgent = WebIdentity.FALLBACK_USER_AGENT;
    return WebIdentity.cachedUserAgent;
  }
}
