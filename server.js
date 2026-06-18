const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 3000;
const SCRIPT_DIR = __dirname;
// We look for files in SCRIPT_DIR, but if a project is mounted, prd.json might be in SCRIPT_DIR/project
// Let's resolve project paths dynamically
const PROJECT_DIR = path.join(SCRIPT_DIR, 'project');

function getProjectFile(filename) {
  // First try SCRIPT_DIR (local run)
  let p = path.join(SCRIPT_DIR, filename);
  if (fs.existsSync(p)) return p;
  
  // Try SCRIPT_DIR/project (docker run)
  p = path.join(PROJECT_DIR, filename);
  if (fs.existsSync(p)) return p;
  
  return null;
}

const server = http.createServer((req, res) => {
  // CORS Headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.statusCode = 204;
    res.end();
    return;
  }

  if (req.url === '/api/status') {
    res.setHeader('Content-Type', 'application/json');
    
    // 1. Live status (status.json is written to SCRIPT_DIR or SCRIPT_DIR/project)
    let statusData = { status: "idle", accounts: [], currentIteration: 0, maxIterations: 10 };
    const statusFile = getProjectFile('status.json') || path.join(SCRIPT_DIR, 'status.json');
    if (fs.existsSync(statusFile)) {
      try {
        statusData = JSON.parse(fs.readFileSync(statusFile, 'utf8'));
      } catch (e) {
        console.error("Error parsing status.json:", e);
      }
    }
    
    // 2. PRD Data
    let prdData = null;
    const prdFile = getProjectFile('prd.json');
    if (prdFile && fs.existsSync(prdFile)) {
      try {
        prdData = JSON.parse(fs.readFileSync(prdFile, 'utf8'));
      } catch (e) {
        console.error("Error parsing prd.json:", e);
      }
    }
    
    // 3. Progress Log
    let progressLog = "";
    const progressFile = getProjectFile('progress.txt');
    if (progressFile && fs.existsSync(progressFile)) {
      try {
        progressLog = fs.readFileSync(progressFile, 'utf8');
      } catch (e) {
        console.error("Error reading progress.txt:", e);
      }
    }
    
    res.end(JSON.stringify({
      status: statusData,
      prd: prdData,
      progress: progressLog
    }));
  } else if (req.url === '/' || req.url === '/index.html') {
    res.setHeader('Content-Type', 'text/html');
    const htmlPath = path.join(SCRIPT_DIR, 'dashboard.html');
    if (fs.existsSync(htmlPath)) {
      res.end(fs.readFileSync(htmlPath));
    } else {
      res.statusCode = 404;
      res.end('<h1>Dashboard file (dashboard.html) not found.</h1>');
    }
  } else {
    res.statusCode = 404;
    res.end('Not Found');
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Ralph Dashboard web server listening on 0.0.0.0:${PORT}`);
});
