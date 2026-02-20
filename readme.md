# AWS WordPress HA Demo (Student Guide)

This repo deploys a simple **high-availability WordPress** stack in AWS using **Terraform** (infrastructure).  
You’ll end up with WordPress reachable in a browser, running across multiple Availability Zones.

> This guide intentionally **leaves out** anything about importing an existing WordPress site.

---

# Prereqs

You will need: 

- An AWS account 
- A Cloudflare account (Sign up for the free plan) 
- A registered domain from Godaddy. any .com, .net or .whatever will work, but it should be a public facing FQDN

You can run this without cloudflare, but that means you'll need a DNS host that can do something called "CNAME Flattening" since the root of the domain, or the `@` record will be pointing to another DNS name, not an IP. AWS load balancer IP's change often and without notice. 

## Cloudflare setup (For terraform automation to work)

This repo automatically creates the required Cloudflare DNS records during `terraform apply`.
Students do **not** need to copy any AWS load balancer DNS names or create DNS records manually.

> If you don't have a registered .com | .net | .whatever, you'll need one, since this lab requires a public facing FQDN. 

### What you need (from Cloudflare)

You need:
- A **Cloudflare API Token** (not the Global API Key)
- Your **Cloudflare Zone ID**
- A domain already added to Cloudflare (zone exists and is active)
- If your domain has not been added to cloudflare yet

#### Adding a domain to cloudflare if you just registered one

- Create a Cloudflare account and verify your email.
- In Cloudflare, click Add a site and enter your domain (e.g., example.com).
- Choose the Free plan.
- Continue through the DNS scan screen (you can accept/continue).
- Cloudflare shows you two nameservers — copy them.
- Log into your domain registrar (where you bought the domain).
- Find the domain’s Nameservers settings.
- Select Custom nameservers and replace the existing nameservers with the two Cloudflare nameservers.
- Save changes at the registrar.
- Back in Cloudflare, wait until the domain status becomes Active.

---

### Step 1: Create a Cloudflare API Token

In Cloudflare:
1. Click your profile (top right) → **My Profile**
2. Go to **API Tokens**
3. Click **Create Token**
4. Use **Create Custom Token** (recommended)

Set permissions like this:

**Permissions**
- `Zone` → `DNS` → `Edit`

**Zone Resources**
- `Include` → `Specific zone` → select your domain

Create the token and copy it.

> Keep this token private. If it leaks, revoke it and create a new one.

---

### Step 2: Get your Cloudflare Zone ID

In Cloudflare:
1. Click **Websites**
2. Select your domain
3. On the **Overview** page, copy the **Zone ID**

---

### Step 3: Put Cloudflare values into `terraform.tfvars`

In the repo root, there is a file named `terraform.tfvars.sample` with:

```hcl
cloudflare_api_token = "PASTE_YOUR_CLOUDFLARE_API_TOKEN_HERE"
cloudflare_zone_id   = "PASTE_YOUR_CLOUDFLARE_ZONE_ID_HERE"
```
Make a copy of the file and name is `terraform.tfvars`


## 1) What AWS account do I need?

### Use a normal AWS account (Free Tier eligible)
Students should create a standard AWS account and do **not** need AWS Organizations, Control Tower, or anything special.

**Strong recommendation:**
- Create a brand-new AWS account just for this lab.
- Use the **root** account only once (billing + MFA + first admin user), then stop using it.

### Cost warning (read this)
This lab can create resources that may cost money. You are responsible for your AWS bill.

Before deploying, do these two things:
1. Set a **Billing Budget** with email alerts.
2. Enable **MFA** on the root account.

---

## 2) AWS setup checklist (do this first)

### 2.1) Create an IAM admin user (so you don’t use root)
1. AWS Console → **IAM**
2. **Users** → Create user (example: `student-admin`)
3. Enable **Console access**
4. Attach policy: **AdministratorAccess**
5. Create an **Access Key** for CLI use
6. Save:
   - Access Key ID
   - Secret Access Key

> Yes, AdministratorAccess is a lab shortcut. Real orgs use least privilege. For class, we optimize for fewer blockers.

### 2.2) Create a billing budget alert
1. AWS Console → **Billing** → **Budgets** → Create budget
2. Choose **Cost budget**
3. Set a budget amount (example: **$10**)
4. Add email alerts at:
   - 80% forecasted
   - 100% actual

### 2.3) Pick your AWS region
Use the region your instructor specifies (common choice: `us-east-2`).

---

## 3) Choose your setup path

- **Windows:** Use the repo’s **VS Code Dev Container** (recommended)
- **Mac:** Install Terraform + Ansible locally (recommended)

Either path ends with the same Terraform commands:
- `terraform init`
- `terraform plan`
- `terraform apply`
- `terraform destroy`

---

## 4) Windows setup (VS Code Dev Containers)

### 4.1) Requirements
Install these first:
- **Git**
- **Docker Desktop**
- **Visual Studio Code**
- VS Code extension: **Dev Containers** (by Microsoft)

### 4.2) Clone the repo
Open PowerShell and run:
```powershell
git clone <REPO_URL>
cd <REPO_FOLDER>
code .
```

### 4.3) Reopen in Dev Container

In VS Code:

Press `Ctrl+Shift+P`

Run: Dev Containers: Reopen in Container

### 4.4) Verify tools inside the container

In the VS Code terminal (inside the container), run:

``` bash
terraform version
ansible --version
aws --version
```

### 4.5) Configure AWS credentials inside the Dev Container

Still inside the container terminal:

``` bash
aws configure
```
Enter:

- AWS Access Key ID
- AWS Secret Access Key
- Default region name (example: us-east-2)
- Default output format: json

Verify:

``` bash
aws sts get-caller-identity
```

## 5) Mac setup (local installs)

### 5.1) Install Homebrew (if you don’t have it)
``` bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 5.2) Install AWS CLI, Terraform, and Ansible

``` bash
brew update
brew install awscli terraform ansible
```

Verify installs:

```bash
aws --version
terraform version
ansible --version
```

### 5.3) Configure AWS credentials

``` bash
aws configure
```

Enter:

- AWS Access Key ID
- AWS Secret Access Key
- Default region name (example: us-east-2)
- Default output format: json

Verify:

``` bash
aws sts get-caller-identity
```

## 6) Deploy (Terraform)

From the repo root:

### 6.1) Initialize
``` bash
terraform init
```
### 6.2) Validate
``` bash
terraform validate
```
### 6.3) Plan
``` bash
terraform plan
```
### 6.4) Apply
``` bash
terraform apply
```
Type `yes` when prompted.

## 7) Get the WordPress URL

the wordpress URL is `https://your-dns-name.com/`


## 8) Complete the WordPress installer

When the site loads, complete the WordPress setup screen:

- Site title
- Admin username
- Admin password
- Admin email

Then log into:

`https://your-dns-name.com/wp-admin`

9) Cleanup (IMPORTANT)

When you’re done, destroy everything to avoid ongoing charges:

``` bash
terraform destroy
```

Type yes when prompted.

## 10) Troubleshooting

### 10.1) Terraform can’t find AWS credentials

Run:

``` bash
aws sts get-caller-identity
```
If it fails, re-run:

``` bash
aws configure
```

### 10.2) AccessDenied errors

Your AWS identity likely lacks permissions. Use the IAM user with AdministratorAccess.

### 10.3) Website doesn’t load right away

Wait a few minutes after apply (instances + health checks need time).

## 11) Safety / good habits

- Don’t use `root` for normal work.
- Destroy resources when done.
- Never share AWS keys or secrets in screenshots, Discord, or docs.