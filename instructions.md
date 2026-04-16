# cloudnative wiki (Quartz)

Welcome to your revamped knowledge base! The internal files and folders have been reorganized into the `content/` folder, and this repository is ready to be published via [Quartz](https://quartz.jzhao.xyz/).

## 🚀 How to Deploy Online with Vercel

Since your files are already prepped, you can seamlessly host your notes on Vercel. Every time you push a new commit to GitHub, Vercel will automatically rebuild and publish your upgraded site.

### Step 1: Push to GitHub

First, create a new **empty repository** on GitHub (without a README, .gitignore, or license). Then, link this local directory to your new GitHub remote and push:

```bash
cd /home/darshan/projects/cloudnative-wiki
git add .
git commit -m "Initial commit of reorganized notes and Quartz setup"
git branch -M main
git remote add origin https://github.com/<your-username>/<your-repo-name>.git
git push -u origin main
```

### Step 2: Connect to Vercel

1. Log in to [Vercel](https://vercel.com/) with your GitHub account.
2. Click **Add New** > **Project**.
3. Locate your newly pushed GitHub repository and click **Import**.
4. In the **Configure Project** section, use the following settings:
   - **Framework Preset**: Other
   - **Build Command**: `npx quartz build`
   - **Output Directory**: `public`
5. Click **Deploy**.

That's it! Vercel will now parse the markdown in your `content/` folder and deploy the static site. Moving forward, simply pushing notes to GitHub will trigger a new Vercel build instantly!

---

## 💻 Local Development (Optional)

### Using Node.js
If you install Node.js/npm on this machine in the future, you can preview the website locally while taking notes:

```bash
# Install dependencies
npm install

# Start Local Preview Server
npx quartz build --serve
```

### Using Docker
Alternatively, since a `Dockerfile` is provided, you can build and test your site locally using Docker without needing Node.js installed:

```bash
# Build the Docker image
docker build -t cloudnative-wiki .

# Run the container and expose port 8080
docker run -p 8080:8080 cloudnative-wiki
```
Once the container is running, navigate to `http://localhost:8080` in your web browser to view your notes live!
