'use strict';
// B&G Dashboard Service Controller
// Runs as a Windows service (NSSM, auto-start, SYSTEM account).
// Exposes a local HTTP API on port 9998 for starting/stopping the
// Signal K service without requiring a PowerShell window.
// Used by the Grafana dashboard Start/Stop links.

const http = require('http');
const { exec } = require('child_process');

const PORT = 9998;
const HOST = '127.0.0.1';

function page(title, body, color) {
    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta http-equiv="refresh" content="3;url=http://localhost:3001">
<title>${title}</title>
<style>
  body { font-family: sans-serif; background: #111217; display: flex;
         align-items: center; justify-content: center; height: 100vh; margin: 0; }
  .box { background: #181b1f; color: #d8d9da; padding: 36px 52px;
         border-radius: 8px; text-align: center; border-left: 4px solid ${color};
         max-width: 420px; }
  h2   { margin: 0 0 10px; color: ${color}; font-size: 1.4rem; }
  p    { margin: 0 0 18px; color: #9fa1a3; font-size: 0.95rem; }
  small{ color: #666; font-size: 0.8rem; }
</style>
</head>
<body>
  <div class="box">
    <h2>${title}</h2>
    <p>${body}</p>
    <small>Returning to Grafana in 3 seconds&hellip;</small>
  </div>
</body>
</html>`;
}

const server = http.createServer((req, res) => {
    const url = req.url.split('?')[0];

    if (url === '/signalk/start') {
        exec('net start signalk', (err, stdout, stderr) => {
            const out = (stdout + stderr).toLowerCase();
            res.writeHead(200, { 'Content-Type': 'text/html' });
            if (!err) {
                res.end(page('Signal K Started',
                    'Signal K is now running. Data will appear in Grafana within 30 seconds.',
                    '#73bf69'));
            } else if (out.includes('already')) {
                res.end(page('Already Running',
                    'Signal K was already running.',
                    '#f2cc0c'));
            } else {
                res.end(page('Error',
                    `Could not start Signal K: ${stderr || err.message}`,
                    '#f2495c'));
            }
        });

    } else if (url === '/signalk/stop') {
        exec('net stop signalk', (err, stdout, stderr) => {
            const out = (stdout + stderr).toLowerCase();
            res.writeHead(200, { 'Content-Type': 'text/html' });
            if (!err) {
                res.end(page('Signal K Stopped',
                    'Signal K is stopped. COM3 is free for Expedition or the Race Logger.',
                    '#5794f2'));
            } else if (out.includes('not started')) {
                res.end(page('Already Stopped',
                    'Signal K was already stopped. COM3 is free.',
                    '#f2cc0c'));
            } else {
                res.end(page('Error',
                    `Could not stop Signal K: ${stderr || err.message}`,
                    '#f2495c'));
            }
        });

    } else if (url === '/signalk/status') {
        exec('sc query signalk', (err, stdout) => {
            const running = !err && stdout.includes('RUNNING');
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ running }));
        });

    } else {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Not found');
    }
});

server.listen(PORT, HOST, () => {
    console.log(`B&G service controller listening on ${HOST}:${PORT}`);
});
