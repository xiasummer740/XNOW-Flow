#!/bin/bash
DEPLOY_SCRIPT="
set -e
cd /opt/xnow-flow-git && git pull
find backend -maxdepth 1 -name '*.py' -exec cp -f {} /opt/xnow-flow/ \;
find backend/routers -name '*.py' -exec cp -f {} /opt/xnow-flow/routers/ \;
find backend/models -name '*.py' -exec cp -f {} /opt/xnow-flow/models/ \;
find backend/schemas -name '*.py' -exec cp -f {} /opt/xnow-flow/schemas/ \;
cd login && npm run build 2>/dev/null
cp dist/index.html /opt/xnow-flow/static/ && mkdir -p /opt/xnow-flow/static/assets
find dist/assets -type f -exec cp -f {} /opt/xnow-flow/static/assets/ \;
sed -i s/tk_number/aweme_number/g seed.py 2>/dev/null
/opt/xnow-flow/venv/bin/python seed.py 2>&1 | tail -2
kill \$(lsof -ti:8000) 2>/dev/null || true
sleep 3
nohup /opt/xnow-flow/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000 > server.log 2>&1 &
sleep 6
curl -s http://127.0.0.1:8000/api/health
"
echo "$DEPLOY_SCRIPT"
