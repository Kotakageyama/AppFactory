const http = require('node:http');

const port = Number(process.env.PORT || 8080);
http.createServer((request, response) => {
  if (request.url === '/healthz') {
    response.writeHead(200, { 'content-type': 'application/json' });
    return response.end(JSON.stringify({ ok: true }));
  }
  response.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' });
  response.end('Application scaffold is running.');
}).listen(port, '0.0.0.0', () => console.log(`Listening on ${port}`));
