Install and configure the self-hosted LLM setup for Claude Code.

Detect whether you are running on the **GPU server** or the **local machine** and perform the appropriate setup steps.

## Step 1 — Detect environment

Run `nvidia-smi` to check if a GPU is present.

- If a GPU is detected: this is the **GPU server** — proceed with GPU Server Setup below.
- If no GPU is detected: this is the **local machine** — proceed with Local Machine Setup below.

## GPU Server Setup

### 1. Check prerequisites

Run the following and report what is found:

```bash
nvidia-smi
nvcc --version
cmake --version
git --version
```

If cmake or git are missing, install them:

```bash
sudo apt-get update -qq && sudo apt-get install -y cmake ninja-build git
```

### 2. Build llama.cpp with CUDA

Check if `~/llama.cpp/build/bin/llama-server` already exists. If it does, skip the build and report it is already installed.

If not, clone and build:

```bash
git clone https://github.com/ggml-org/llama.cpp ~/llama.cpp
cd ~/llama.cpp
cmake -B build -G Ninja -DGGML_CUDA=ON
cmake --build build --config Release -j $(nproc)
```

Verify the build succeeded:

```bash
~/llama.cpp/build/bin/llama-server --version
```

### 3. Check if model is already downloaded

Check if the Qwen model exists in the HuggingFace cache:

```bash
ls ~/.cache/huggingface/hub/ 2>/dev/null
```

Report whether the model is already cached or needs to be downloaded (~22GB on first run).

### 4. Start the model server

Ask the user: "Start the model server now? It will download ~22GB on first run and may take several minutes. (yes/no)"

If yes, start the server:

```bash
nohup ~/llama.cpp/build/bin/llama-server \
  -hf unsloth/Qwen3.5-35B-A3B-GGUF:Q4_K_M \
  --host 127.0.0.1 \
  --port 8131 \
  -ngl 999 \
  -t 2 \
  -c 131072 \
  -b 512 \
  -ub 1024 \
  --parallel 1 \
  -fa on \
  --jinja \
  --keep 1024 \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --swa-full \
  --no-context-shift \
  --reasoning off \
  --mlock \
  --no-mmap \
  > /tmp/llama-server.log 2>&1 &
```

Wait 10 seconds, then verify the server is responding:

```bash
curl -s http://localhost:8131/v1/models
```

Report the model name from the response and confirm the server is ready.

### 5. Print connection instructions

Print the public IP of this server:

```bash
curl -s ifconfig.me
```

Tell the user:

"GPU server setup complete. Now run `/install` on your local machine and provide this IP when prompted."

---

## Local Machine Setup

### 1. Check Claude Code is installed

```bash
claude --version
```

If not installed, instruct the user to install it:

```bash
npm install -g @anthropic-ai/claude-code
```

### 2. Check SSH key

Ask the user: "What is the path to your SSH key for the GPU server? (e.g. ~/.ssh/my-key.pem)"

Verify the key file exists at the path provided.

### 3. Ask for GPU server IP

Ask the user: "What is the public IP address of your GPU server?"

Store it as G6E_IP.

### 4. Test SSH connectivity

```bash
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i <key> ubuntu@<G6E_IP> echo "ok"
```

If this fails, report the error and suggest checking:
- Security group allows port 22 from the current IP
- The correct username (ubuntu for Deep Learning AMI)
- The key file has correct permissions (`chmod 600 <key>`)

### 5. Open SSH tunnel

```bash
export G6E_IP=<ip>
export G6E_KEY=<key>
./scripts/tunnel.sh start
```

Verify the tunnel is working:

```bash
curl -s http://localhost:8131/v1/models
```

Report the model name from the response.

### 6. Configure Claude Code settings

Back up any existing Claude Code settings:

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.backup 2>/dev/null || true
```

Copy the template settings:

```bash
cp config/settings.template.json ~/.claude/settings.json
```

### 7. Verify end-to-end

Run a quick test:

```bash
claude -p "Reply with only the words: setup complete"
```

If the response contains "setup complete", the full chain is working.

### 8. Print summary

Print a summary of what was configured:

- GPU server IP
- SSH tunnel status
- Model responding at localhost:8131
- Claude Code settings updated

Tell the user:
"Setup complete. Run `./scripts/claude-local.sh` to start a Claude Code session backed by your self-hosted model. Your original Claude Code settings have been backed up to ~/.claude/settings.json.backup."
