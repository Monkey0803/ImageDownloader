#!/usr/bin/env node
// Local-only fixture. Forward with: hdc rport tcp:18767 tcp:18767
const http = require('node:http');
const zlib = require('node:zlib');
function crc(bytes) {
  let c = 0xffffffff;
  for (const b of bytes) {
    c ^= b;
    for (let i = 0; i < 8; i++) c = (c >>> 1) ^ (c & 1 ? 0xedb88320 : 0);
  }
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(name, body) {
  const type = Buffer.from(name), length = Buffer.alloc(4), check = Buffer.alloc(4);
  length.writeUInt32BE(body.length); check.writeUInt32BE(crc(Buffer.concat([type, body])));
  return Buffer.concat([length, type, body, check]);
}
function png(r, g, b) {
  const width = 400, height = 300, header = Buffer.alloc(13);
  header.writeUInt32BE(width); header.writeUInt32BE(height, 4); header[8] = 8; header[9] = 2;
  const pixels = Buffer.alloc((width * 3 + 1) * height);
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const i = y * (width * 3 + 1) + 1 + x * 3;
    pixels[i] = r; pixels[i + 1] = g; pixels[i + 2] = b;
  }
  return Buffer.concat([Buffer.from('89504e470d0a1a0a', 'hex'), chunk('IHDR', header),
    chunk('IDAT', zlib.deflateSync(pixels)), chunk('IEND', Buffer.alloc(0))]);
}
const pictures = { '/a.png': png(32, 110, 210), '/b.png': png(30, 175, 110),
  '/protected.png': png(210, 80, 45), '/image': png(150, 60, 190) };
const pages = {
  '/one.html': '<title>BatchFixtureOne</title><img src="/a.png" width="240"><div style="height:1400px"></div>'
    + '<img id="lazy" data-src="/protected.png" width="240"><script>'
    + 'setTimeout(()=>{const i=new Image();i.src="/b.png";document.body.prepend(i)},700);'
    + 'addEventListener("scroll",()=>{document.querySelector("#lazy").src="/protected.png"})</script>',
  '/two': '<title>BatchFixtureTwo</title><img src="/b.png" width="240"><img src="/a.png?sign=one" width="240">',
  '/login.html': '<title>请先登录</title><h1>请先登录</h1><p>Fixture login interception</p>',
  '/empty.html': '<title>BatchFixtureEmpty</title><p>No images</p>'
};
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://127.0.0.1');
  console.log(req.method, url.pathname, req.headers.referer || '-');
  if (url.pathname === '/slow.html') return;
  if (req.method === 'HEAD' && ['/two', '/image'].includes(url.pathname)) { res.writeHead(405); return res.end(); }
  if (url.pathname === '/protected.png'
    && !String(req.headers.referer || '').includes('/one.html')) {
    res.writeHead(403, { 'Content-Type': 'text/plain' }); return res.end('Referer required');
  }
  const body = pictures[url.pathname] || pages[url.pathname];
  if (!body) { res.writeHead(404); return res.end('missing fixture'); }
  res.writeHead(200, { 'Content-Type': pictures[url.pathname] ? 'image/png' : 'text/html; charset=utf-8',
    'Content-Length': Buffer.byteLength(body), 'Cache-Control': 'no-store' });
  res.end(req.method === 'HEAD' ? undefined : body);
});
server.listen(18767, '127.0.0.1', () => console.log('Batch fixture: http://127.0.0.1:18767'));
