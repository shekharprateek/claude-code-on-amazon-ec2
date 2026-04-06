# Claude Code on Amazon EC2 with a Self-Hosted Open-Source Model

Run Claude Code — Anthropic's AI coding assistant — backed by an open-source model on
Amazon EC2. Your code stays inside your AWS account, costs are predictable, and you keep
full control over the model.

```text
Your Machine
  │
  │  SSH tunnel (encrypted, no open ports needed)
  │
  ▼
Amazon EC2 GPU Instance (g6e.xlarge)
  Open-source model (Qwen 3.5-35B) via llama.cpp
  NVIDIA L40S, 45GB VRAM — runs fully within your VPC
```

## Why Run on EC2?

| | Cloud API (Anthropic / Amazon Bedrock) | Self-Hosted on EC2 |
| --- | --- | --- |
| Pricing | Per token — variable cost | Fixed hourly EC2 rate |
| Data residency | Sent to external API | Stays in your AWS account |
| Model choice | Provider-managed | Any open-source model |
| Network path | Public internet | Within your VPC |
| Compliance controls | Limited | Full — IAM, VPC, CloudTrail |

Heavy coding sessions with many tool calls (file reads, edits, bash commands) add up fast
on pay-per-token APIs. At ~117 tokens/sec on a g6e.xlarge, a self-hosted model is
cost-effective for sustained daily use.

## Choosing an EC2 Instance

| Instance | GPU | VRAM | On-Demand | Best For |
| --- | --- | --- | --- | --- |
| g6e.xlarge | NVIDIA L40S | 45GB | ~$1.86/hr | 35B models, recommended |
| g5.xlarge | NVIDIA A10G | 24GB | ~$1.01/hr | 7B-13B models |
| g4dn.xlarge | NVIDIA T4 | 16GB | ~$0.53/hr | 7B models, budget option |
| p3.2xlarge | NVIDIA V100 | 16GB | ~$3.06/hr | Older generation |

## Prerequisites

- AWS account with EC2 access
- AWS CLI configured (`aws configure`)
- Claude Code installed locally (`npm install -g @anthropic-ai/claude-code`)
- An EC2 key pair

## What's Inside

| File | What it does |
| --- | --- |
| [SETUP-GUIDE.md](SETUP-GUIDE.md) | Full walkthrough with AWS-specific steps, flags, and troubleshooting |
| [scripts/tunnel.sh](scripts/tunnel.sh) | Opens and closes the SSH tunnel between your machine and EC2 |
| [scripts/claude-local.sh](scripts/claude-local.sh) | Launches Claude Code pointed at the local model, restores config on exit |
| [scripts/bench.sh](scripts/bench.sh) | Benchmarks local model vs Amazon Bedrock side by side |
| [config/settings.template.json](config/settings.template.json) | Claude Code configuration template |

## Quick Start

### Step 1 — Launch the EC2 instance

Use the **Deep Learning Base OSS Nvidia Driver AMI (Ubuntu 22.04)** — NVIDIA drivers and
CUDA come pre-installed.

```bash
aws ec2 run-instances \
  --region us-east-1 \
  --image-id ami-014135eb43056a305 \
  --instance-type g6e.xlarge \
  --key-name <your-key-pair> \
  --security-group-ids <your-sg> \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":100,"VolumeType":"gp3"}}]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=llm-server}]'
```

Security group: port 22 inbound from your IP only. The model port never needs to be
open — access is via SSH tunnel.

### Step 2 — Build the model server on EC2

SSH in and run:

```bash
sudo apt-get update -qq && sudo apt-get install -y cmake ninja-build git

git clone https://github.com/ggml-org/llama.cpp ~/llama.cpp
cd ~/llama.cpp
cmake -B build -G Ninja -DGGML_CUDA=ON
cmake --build build --config Release -j $(nproc)
```

Start the model (~22GB downloads on first run):

```bash
nohup ~/llama.cpp/build/bin/llama-server \
  -hf unsloth/Qwen3.5-35B-A3B-GGUF:Q4_K_M \
  --host 127.0.0.1 --port 8131 \
  -ngl 999 -c 131072 --reasoning off --swa-full --no-context-shift \
  > /tmp/llama-server.log 2>&1 &
```

### Step 3 — Connect from your machine

```bash
export G6E_IP=<your-ec2-public-ip>
export G6E_KEY=~/.ssh/<your-key>.pem
./scripts/tunnel.sh start
```

### Step 4 — Run Claude Code

```bash
./scripts/claude-local.sh
```

Or run `/install` inside Claude Code for a guided setup experience.

See [SETUP-GUIDE.md](SETUP-GUIDE.md) for the full walkthrough including CloudWatch
monitoring, spot instance setup, and cost optimization.

## Cost Optimization

**Stop when not in use** — model weights persist on EBS and reload in seconds:

```bash
aws ec2 stop-instances --instance-ids <instance-id>
aws ec2 start-instances --instance-ids <instance-id>
```

**Spot instances** save up to 70% for interruptible workloads:

```bash
aws ec2 request-spot-instances \
  --instance-count 1 \
  --type one-time \
  --launch-specification \
    '{"ImageId":"ami-014135eb43056a305","InstanceType":"g6e.xlarge","KeyName":"<key>","SecurityGroupIds":["<sg>"]}'
```

## Monitor GPU Usage

Live on the instance:

```bash
nvidia-smi --query-gpu=utilization.gpu,memory.used,temperature.gpu \
  --format=csv --loop=1
```

## Benchmark vs Amazon Bedrock

Run the same coding tasks against both backends and compare:

```bash
./scripts/bench.sh both
```

## Tear Down

```bash
aws ec2 terminate-instances --region us-east-1 --instance-ids <instance-id>
aws ec2 delete-security-group --region us-east-1 --group-id <sg-id>
```
