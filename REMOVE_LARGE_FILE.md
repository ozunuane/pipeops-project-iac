# 🗑️ Remove Large File from Git History

## Problem
The `AWSCLIV2.pkg` file (50.43 MB) was accidentally committed and pushed to GitHub. This file should not be in version control.

## Solution Options

### ⚡ Option 1: Quick Fix (Recommended for Recent Commits)

If this was in your most recent commit, you can amend it:

```bash
# Remove the file from Git tracking
git rm --cached AWSCLIV2.pkg

# Delete the file from your working directory
rm AWSCLIV2.pkg

# Amend the last commit
git commit --amend -m "chore: remove AWS CLI installer from repository"

# Force push (⚠️ WARNING: This rewrites history)
git push origin main --force
```

### 🔧 Option 2: Remove from Git History (If file is in older commits)

Use `git filter-repo` (recommended) or `git filter-branch`:

#### Using git filter-repo (Better Performance)

```bash
# Install git-filter-repo if not already installed
# macOS:
brew install git-filter-repo

# Remove the file from all history
git filter-repo --path AWSCLIV2.pkg --invert-paths

# Force push to remote
git push origin main --force
```

#### Using BFG Repo-Cleaner (Fastest)

```bash
# Install BFG
brew install bfg

# Clone a fresh copy (BFG requires this)
cd ..
git clone --mirror https://github.com/ozunuane/pipeops-project-iac.git

# Remove the file
bfg --delete-files AWSCLIV2.pkg pipeops-project-iac.git

# Clean up and push
cd pipeops-project-iac.git
git reflog expire --expire=now --all
git gc --prune=now --aggressive
git push --force
```

### 🛡️ Option 3: Keep History, Just Remove from Future Commits

If you don't want to rewrite history (safest for shared repos):

```bash
# Remove from tracking but keep in working directory temporarily
git rm --cached AWSCLIV2.pkg

# Commit the removal
git commit -m "chore: stop tracking AWSCLIV2.pkg"

# Delete the actual file
rm AWSCLIV2.pkg

# Commit the deletion
git commit -am "chore: remove AWS CLI installer file"

# Push changes
git push origin main
```

**Note:** This keeps the file in Git history, so your repo size won't decrease.

## 📋 Step-by-Step: Recommended Approach

### Step 1: Backup Your Work
```bash
# Create a backup branch
git branch backup-before-cleanup
```

### Step 2: Remove the File
```bash
# Remove from Git index
git rm --cached AWSCLIV2.pkg

# Commit the change
git commit -m "chore: remove AWSCLIV2.pkg from tracking"
```

### Step 3: Verify .gitignore
```bash
# Verify the file is ignored
git check-ignore -v AWSCLIV2.pkg
# Should output: .gitignore:XXX:*.pkg    AWSCLIV2.pkg
```

### Step 4: Clean Up History (Optional but Recommended)
```bash
# Install git-filter-repo
brew install git-filter-repo

# Remove from all history
git filter-repo --path AWSCLIV2.pkg --invert-paths --force
```

### Step 5: Force Push
```bash
# ⚠️ WARNING: This rewrites history. Coordinate with your team!
git push origin main --force
```

### Step 6: Clean Up Local Repository
```bash
# Remove the actual file
rm AWSCLIV2.pkg

# Clean up Git's internal cache
git gc --aggressive --prune=now
```

## 🔍 Verify the Fix

```bash
# Check file is not tracked
git ls-files | grep AWSCLIV2.pkg
# Should return nothing

# Check repo size
du -sh .git
# Should be smaller after cleanup

# Verify .gitignore is working
echo "test" > test.pkg
git status
# Should not show test.pkg as untracked
rm test.pkg
```

## ⚠️ Important Warnings

1. **Force Push Impact**: Force pushing rewrites history. If others have cloned the repo, they'll need to:
   ```bash
   git fetch origin
   git reset --hard origin/main
   ```

2. **Coordinate with Team**: Inform your team before force pushing.

3. **GitHub Size Limits**:
   - GitHub warns at 50 MB
   - GitHub blocks files > 100 MB
   - Large files slow down clone/fetch operations

4. **Alternative for Large Files**: Consider using Git LFS (Large File Storage) for legitimate large files:
   ```bash
   git lfs install
   git lfs track "*.pkg"
   ```

## 📊 Check Repository Size

Before cleanup:
```bash
git count-objects -vH
```

After cleanup:
```bash
git count-objects -vH
```

## 🎯 Prevention

Your updated `.gitignore` now prevents this from happening again by ignoring:
- `*.pkg` files
- `*.dmg` files
- All installer formats
- `AWSCLIV2.pkg` specifically

## 📚 Additional Resources

- [GitHub: Removing sensitive data](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)
- [git-filter-repo documentation](https://github.com/newren/git-filter-repo)
- [BFG Repo-Cleaner](https://rtyley.github.io/bfg-repo-cleaner/)

---

**Need Help?** Run the commands step by step and verify each step before proceeding to the next.
