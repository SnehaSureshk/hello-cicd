# CI/CD Tutorial: GitHub Actions + Docker + AWS EC2 (Free Tier)

Edit `app/index.html`, run `git push`, and about a minute later the new page is live on AWS without any manual steps.

```
 ┌──────────┐  git push  ┌──────────────────┐  docker push  ┌────────────┐
 │  Laptop  │ ─────────▶ │  GitHub Actions  │ ────────────▶ │ Docker Hub │
 └──────────┘            │  1. build image  │               └─────┬──────┘
                         │  2. SSH to EC2   │ ──ssh──┐            │ docker pull
                         └──────────────────┘        ▼            ▼
                                               ┌───────────────────────┐
                                               │ AWS EC2 (t3.micro)    │
                                               │ nginx container :80   │
                                               └───────────────────────┘
```

## Project structure

```
hello-html-aws/
├── app/index.html                 # the website (edit this!)
├── Dockerfile                     # nginx:alpine + our HTML
├── .dockerignore
├── scripts/ec2-user-data.sh       # installs Docker on the EC2 instance
└── .github/workflows/deploy.yml   # the CI/CD pipeline
```

## What you need

- A GitHub account
- A Docker Hub account (free): https://hub.docker.com
- An AWS account (Free Tier)
- Git installed on your machine. Docker on your machine is optional (only for Step 1).

---

## Step 1: Run it locally (optional)

```bash
docker build -t hello-cicd --build-arg GIT_SHA=local-test .
docker run --rm -p 8080:80 hello-cicd
```

Open http://localhost:8080. The page should say **Version: local-test**.

> **Why the version?** The Dockerfile swaps `__VERSION__` in the HTML for the Git commit SHA.
> After each deploy you can see exactly which commit is live.

---

## Step 2: Launch an EC2 instance

1. In the AWS Console, go to **EC2 → Launch instance**.
2. **Name:** `hello-cicd`
3. **AMI:** Amazon Linux 2023
4. **Instance type:** `t3.micro` (or `t2.micro`). Pick one labelled *Free tier eligible*.
5. **Key pair:** create a new one called `hello-cicd-key` (RSA, `.pem`). **Download it and keep it safe.**
6. **Network settings → Edit → Security group rules:**

   | Type | Port | Source    | Why                                     |
   |------|------|-----------|-----------------------------------------|
   | SSH  | 22   | 0.0.0.0/0 | GitHub Actions runners use changing IPs |
   | HTTP | 80   | 0.0.0.0/0 | So anyone can see the site              |

7. **Advanced details → User data:** paste the contents of `scripts/ec2-user-data.sh`.
8. Click **Launch instance**. Wait about 2 minutes, then copy the **Public IPv4 address**.

Check that Docker was installed:

```bash
chmod 400 hello-cicd-key.pem
ssh -i hello-cicd-key.pem ec2-user@<PUBLIC_IP>
docker ps          # should print an empty table (no "permission denied")
exit
```

> On Windows, run these commands in Git Bash or PowerShell. PowerShell has `ssh` built in.
> If `chmod` doesn't work, right-click the .pem file → Properties → Security and remove access for everyone except your own user.

> **Tip:** The public IP changes when you stop and start the instance. For a fixed IP, attach an **Elastic IP**.
> AWS charges for public IPv4 addresses, so check the Billing page to see what your free tier covers.

---

## Step 3: Initial manual deployment

Before we automate anything, deploy once by hand so you know what the pipeline will do:

```bash
# on your laptop
docker login
docker build -t <DOCKERHUB_USER>/hello-cicd:latest --build-arg GIT_SHA=manual .
docker push <DOCKERHUB_USER>/hello-cicd:latest

# on the EC2 instance
ssh -i hello-cicd-key.pem ec2-user@<PUBLIC_IP>
docker run -d --name hello-cicd -p 80:80 --restart unless-stopped <DOCKERHUB_USER>/hello-cicd:latest
```

Open `http://<PUBLIC_IP>`. You should see **Hello, World!** with **Version: manual**. 🎉

Every CI/CD pipeline starts from this manual process. The workflow file just automates it.

---

## Step 4: Create a Docker Hub access token

Docker Hub → **Account settings → Personal access tokens → Generate new token**

- Description: `github-actions`
- Permissions: **Read & Write**

Copy the token. Docker Hub only shows it once.

---

## Step 5: Commit the code (don't push yet)

Create an **empty** repository on GitHub called `hello-cicd`, then:

```bash
cd hello-html-aws
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/<GITHUB_USER>/hello-cicd.git
```

**Don't push yet.** The first push starts the pipeline, and the pipeline needs the secrets from Step 6.

---

## Step 6: Add GitHub secrets, then push

Repo → **Settings → Secrets and variables → Actions → New repository secret**

| Secret name          | Value                                                                                |
|----------------------|--------------------------------------------------------------------------------------|
| `DOCKERHUB_USERNAME` | your Docker Hub username                                                             |
| `DOCKERHUB_TOKEN`    | the token from Step 4                                                                |
| `EC2_HOST`           | EC2 public IP, e.g. `13.233.10.20`                                                   |
| `EC2_SSH_KEY`        | the **entire** contents of `hello-cicd-key.pem`, including the `-----BEGIN` / `-----END` lines |

> Never commit the `.pem` file or tokens to the repo. Secrets are encrypted, and GitHub hides them in logs as `***`.

Now push:

```bash
git push -u origin main
```

---

## Step 7: Watch the pipeline

Go to the **Actions** tab in your repo. You'll see **Build and Deploy to EC2** running with two jobs:

1. **Build & push Docker image** checks out the code, logs in to Docker Hub, builds the image, and pushes it with two tags: `latest` and the commit SHA.
2. **Deploy to EC2** (runs only if the build succeeds) SSHes into the instance, pulls the new image, replaces the old container, and cleans up old images.
   It then runs a **smoke test**: it `curl`s the site and fails if the new commit SHA isn't on the page.

When both jobs are green, refresh `http://<PUBLIC_IP>`. The version now shows the full commit SHA.

---

## Step 8: The CI/CD moment ✨

Edit `app/index.html`:

```html
<h1>Hello, Techolas! 🚀</h1>
```

```bash
git add app/index.html
git commit -m "Change greeting"
git push
```

Watch the Actions tab. About a minute later, refresh the browser to see the new greeting and a new version SHA, and you never touched the server.

---

## Understanding `deploy.yml`

```yaml
on:
  push:
    branches: [main]      # trigger: every push to main
  workflow_dispatch:      # plus a manual "Run workflow" button
```

```yaml
deploy:
  needs: build            # jobs run in parallel by default; `needs` makes deploy wait for build
```

```bash
docker rm -f hello-cicd || true              # remove old container (|| true = don't fail if none exists)
docker run -d ... --restart unless-stopped   # restart automatically if EC2 reboots
docker image prune -af                       # delete unused images so the 8 GB disk doesn't fill up
```

**Why tag with the commit SHA instead of only `latest`?**
Each SHA tag is immutable and traceable. To roll back, run the old SHA's image:
`docker run ... <user>/hello-cicd:<old-sha>`

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `ssh: handshake failed` / `unable to authenticate` | `EC2_SSH_KEY` must be the whole .pem file, including the BEGIN/END lines. Username must be `ec2-user` (on an Ubuntu AMI it's `ubuntu`). |
| `dial tcp ...:22: i/o timeout` | The security group doesn't allow port 22, or `EC2_HOST` is wrong or stale (the IP changed after a stop/start). |
| `permission denied ... docker.sock` | User data didn't run. SSH in and run `sudo usermod -aG docker ec2-user`, then log out and back in. |
| `denied: requested access to the resource is denied` | Docker Hub token needs **Read & Write**, and `DOCKERHUB_USERNAME` must match exactly. |
| Smoke test fails but deploy succeeded | Port 80 isn't open in the security group, or the container crashed. SSH in and run `docker logs hello-cicd`. |
| Logs show `***/hello-cicd` | This is normal. The username comes from a secret, so GitHub masks it. |

---

## Clean up (avoid charges)

When you're done: **EC2 → Instances → Terminate**. Also release any **Elastic IP** you allocated, because AWS charges for idle Elastic IPs.

---

## Extensions for students

1. Add a **CI job** that validates the HTML (e.g. `npx html-validate app/index.html`) and make `build` depend on it.
2. Swap Docker Hub for **Amazon ECR**, and use `aws-actions/configure-aws-credentials` with GitHub OIDC so the pipeline needs no stored AWS keys.
3. Deploy on **pull requests** to a staging container on port 8080.
4. Replace SSH with **AWS Systems Manager (SSM) Run Command** so port 22 can be closed.
