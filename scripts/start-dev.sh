#!/bin/bash
# Robust dev server starter that keeps running
cd /home/z/my-project
pkill -f "next" 2>/dev/null
sleep 2

# Start dev server with full detachment
nohup bash -c 'exec bun run dev' > /tmp/dev.log 2>&1 &
DEVPID=$!
echo $DEVPID > /tmp/dev.pid
echo "Dev PID: $DEVPID"

# Wait for server to be ready
for i in $(seq 1 30); do
  if curl -s http://localhost:3000/api/auth -X POST -H "Content-Type: application/json" -d '{"username":"admin","password":"admin123"}' 2>/dev/null | grep -q "Login successful"; then
    echo "✓ Server ready at attempt $i"
    exit 0
  fi
  sleep 2
done
echo "✗ Server failed to start"
exit 1
