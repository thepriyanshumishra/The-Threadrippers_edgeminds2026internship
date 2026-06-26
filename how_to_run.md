# Kivo Workspace — Multi-Environment Deployment & Testing Guide

This documentation provides step-by-step instructions on how to set up, test, and run **Kivo Workspace** using the interactive launcher script (`start.sh`) across three target environments:
1. **NVIDIA Jetson Edge AI Environment (Nano or Orin)**
2. **Virtual Machine or Standard Linux Environment (Ubuntu)**
3. **Google Colab or Kaggle Cloud GPU Environment**

---

## 1. NVIDIA Jetson Edge AI Environment (Nano or Orin)

Use this guide for headless, resource-constrained NVIDIA Jetson devices accessed over a secure SSH network connection.

### Step-by-Step Instructions:

1. **Establish SSH Connection:**
   Connect to your Jetson board from your client computer:
   ```bash
   ssh <username>@<jetson-ip> -p <port>
   ```

2. **Clone the Repository:**
   Clone the workspace project on the Jetson board:
   ```bash
   git clone https://github.com/thepriyanshumishra/The-Threadrippers_edgeminds2026internship.git
   cd The-Threadrippers_edgeminds2026internship
   ```

3. **Launch the Setup Script:**
   ```bash
   bash start.sh
   ```

4. **Respond to the Interactive Prompts:**
   * **System Dependencies:** Press **Enter** to auto-install missing packages. The script will install `zstd` (for Ollama archives), `unzip` (for tunnels), and `pciutils` (`lspci` required by Ollama to detect NVIDIA JetPack components).
   * **Rebuild Web UI:** Press **Enter** (or type `n`) to skip compiling the Flutter app. Reusing the pre-compiled build is highly recommended on Jetson boards to save memory and CPU.
   * **Ollama Installation:** Confirm installation if prompted. The script automatically exports the necessary Jetson CUDA runtime directories (`/usr/local/cuda/lib64` and `/usr/local/cuda/targets/aarch64-linux/lib`) to ensure Ollama runs with GPU acceleration.
   * **Tunnel Selection:** Select **Option 4 (ngrok)**. This is the most reliable option for headless remote edge evaluations.
   * **ngrok Auth Token:** Simply press **Enter** to automatically use our pre-configured team evaluation token.

5. **Access and Test:**
   Open the generated ngrok URL (`https://xxxx.ngrok-free.app`) in your client web browser. Navigate to settings and pull a lightweight model (e.g., `qwen2.5:1.5b` or `llama3.2:3b`) to begin chatting with documents.

---

## 2. Virtual Machine or Standard Linux Environment (Ubuntu)

Use this guide to run Kivo Workspace on a standard desktop/server Linux installation or a local Virtual Machine (VM).

### Step-by-Step Instructions:

1. **Install Prerequisites:**
   Open your VM terminal and make sure git and curl are installed:
   ```bash
   sudo apt update && sudo apt install -y git curl
   ```

2. **Clone the Repository:**
   Download the source code onto your VM:
   ```bash
   git clone https://github.com/thepriyanshumishra/The-Threadrippers_edgeminds2026internship.git
   cd The-Threadrippers_edgeminds2026internship
   ```

3. **Start the Interactive Launcher:**
   Run the startup script:
   ```bash
   bash start.sh
   ```

4. **Respond to the Interactive Prompts:**
   * **System Dependencies:** The scanner will detect missing tools (like `python3-venv`, `ffmpeg`, `tesseract-ocr`, `zstd`, `unzip`). When asked: `Do you want to install them automatically? (Requires sudo) [Y/n]:`, press **Enter** (or type `y`) and input your VM password.
   * **Rebuild Web UI:** The script will find the pre-compiled web folder inside the repository. When asked: `Pre-compiled Web UI exists. Rebuild web frontend? [y/N]:`, press **Enter** (or type `n`) to skip compiling and save time.
   * **Ollama Auto-Install:** If Ollama is not active on your VM, it will prompt: `Do you want to attempt auto-installing and starting Ollama? [y/N]:`. Press **Enter** (or type `y`) to install and start the background model daemon.
   * **Public Tunnel:** The script will present a menu to expose a public link. Select **Option 2 (Cloudflare Quick Tunnel)**.

5. **Access the App:**
   Wait for the tunnel to connect. The script will print a green success panel showing your public tunnel link (e.g., `https://xxxx.trycloudflare.com`). You can copy this link and open it in your host machine's browser (e.g., on macOS) to access and test the app.

---

## 3. Google Colab or Kaggle Cloud GPU Environment

Use this guide to test Kivo Workspace inside a free cloud environment equipped with NVIDIA GPUs (such as a T4 or L4 instance). Because notebooks are non-interactive by default, we establish an SSH bridge to run Kivo Workspace interactively.

### Step-by-Step Instructions:

1. **Configure SSH Server (Notebook Cell 1):**
   Create a new cell in your Colab/Kaggle notebook, paste the following code, and run it. This installs the SSH server, overrides default Ubuntu policies, and configures the password to `edge123`:
   ```bash
   # Remove Ubuntu overrides and set clean authentication configurations
   !rm -f /etc/ssh/sshd_config.d/*.conf
   !echo "PermitRootLogin yes" > /etc/ssh/sshd_config
   !echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
   !echo "ChallengeResponseAuthentication no" >> /etc/ssh/sshd_config
   !echo "UsePAM yes" >> /etc/ssh/sshd_config
   !echo "Subsystem sftp /usr/lib/openssh/sftp-server" >> /etc/ssh/sshd_config
   !echo 'root:edge123' | chpasswd

   # Generate host keys and start service
   !ssh-keygen -A
   !mkdir -p /run/sshd
   !service ssh restart
   ```

2. **Expose SSH Port via Bore TCP Tunnel (Notebook Cell 2):**
   Create a second cell, paste the following Python code, and run it. This starts a lightweight TCP tunnel using Bore and prints the exact connection command:
   ```python
   import subprocess, time, os, re

   # Download bore client if missing
   if not os.path.exists("/usr/local/bin/bore"):
       subprocess.run("curl -sL https://github.com/ekzhang/bore/releases/download/v0.5.0/bore-v0.5.0-x86_64-unknown-linux-musl.tar.gz | tar zxf - -C /usr/local/bin", shell=True)
       subprocess.run("chmod +x /usr/local/bin/bore", shell=True)

   # Stop previous tunnels
   subprocess.run("pkill -f bore", shell=True)

   # Start the tunnel in the background
   print("Starting SSH tunnel on port 22...")
   with open("bore.log", "w") as f:
       subprocess.Popen("bore local 22 --to bore.pub", shell=True, stdout=f, stderr=f)

   time.sleep(3)

   with open("bore.log", "r") as f:
       log_content = f.read()

   # Match public port from logs
   match = re.search(r'bore\.pub:(\d+)', log_content)

   if match:
       port = match.group(1)
       print("\n✅ SSH Tunnel Ready!")
       print(f"\n💻 Run this command in your local terminal:\nssh -p {port} root@bore.pub")
       print("\n🔑 Password: edge123")
   else:
       print("\n❌ Failed to establish tunnel. Please rerun the cell.")
   ```

3. **Login from your Local Computer:**
   Open a terminal on your local computer, paste the printed SSH command (e.g. `ssh -p 5357 root@bore.pub`), type `yes` to confirm host authenticity, and enter the password `edge123`.

4. **Clone & Run inside the SSH Session:**
   Now that you have full interactive bash access to the GPU container, run:
   ```bash
   git clone https://github.com/thepriyanshumishra/The-Threadrippers_edgeminds2026internship.git
   cd The-Threadrippers_edgeminds2026internship
   bash start.sh
   ```

5. **Respond to Interactive Prompts:**
   * Run the installer to set up the backend.
   * **Rebuild Web UI:** Since you are in a cloud VM, select **No** to reuse the pre-compiled UI.
   * **Ollama Service:** Confirm installation. The script will automatically start the background Ollama daemon with Nvidia drivers mapped for full GPU acceleration.
   * **Tunnel Selection:** Choose **Option 2 (Cloudflare Quick Tunnel)**. Once connection completes, open the generated `https://xxxx.trycloudflare.com` URL in your PC browser.
