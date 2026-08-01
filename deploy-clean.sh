#!/bin/bash
set -e
cd /opt/xnow-flow-git
git pull
cp -f backend/main.py /opt/xnow-flow/main.py
cp -rf backend/routers /opt/xnow-flow/
cp -rf backend/models /opt/xnow-flow/
cp -rf backend/schemas /opt/xnow-flow/
cd login
npm run build
cp -f dist/index.html /opt/xnow-flow/static/index.html
cp -rf dist/assets /opt/xnow-flow/static/
cd /opt/xnow-flow
sed -i s/tk_number/aweme_number/g seed.py
/opt/xnow-flow/venv/bin/python seed.py
fuser -k 8000/tcp 2>/dev/null || true
sleep 3
nohup /opt/xnow-flow/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000 > server.log 2>&1 &
sleep 6
curl -s http://127.0.0.1:8000/api/health
