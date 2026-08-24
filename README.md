# ProShop — Production-Style Django Deployment on Multi-VM Infrastructure on Centos 9

> A production-style deployment of a Django e-commerce application on a 4-VM Vagrant infrastructure featuring load balancing, automated provisioning, database backup, and server health monitoring.

---


NOTE : please create a .env file with this information   

SECRET_KEY=<secret_key>
DB_USER=<username>
DB_PASSWORD=<password>


## Table of Contents

- [Project Overview](#project-overview)
- [Architecture](#architecture)
- [Technology Stack](#technology-stack)
- [Infrastructure Details](#infrastructure-details)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Environment Configuration](#environment-configuration)
- [Project Structure](#project-structure)
- [Scripts Overview](#scripts-overview)
- [Monitoring & Backup](#monitoring--backup)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)
- [Future Scope](#future-scope)
- [Author](#author)

---

## Project Overview

This project demonstrates a **production-style deployment** of a Django e-commerce application (ProShop) using a 4-VM Vagrant infrastructure. The primary objective is to replicate real-world DevOps practices including infrastructure automation, load balancing, database management, health monitoring, and automated backups — all provisioned through a single command.

### Problem Statement

Deploying a web application in a reproducible, scalable, and production-ready manner is a core challenge in modern software development. This project addresses that challenge by implementing:

- **Infrastructure as Code (IaC)** using Vagrant and Bash provisioning scripts
- **3-Tier Architecture** separating the load balancer, application servers, and database
- **Horizontal Scalability** through a load balancer distributing traffic across multiple application servers
- **Automated Operations** including database backups and server health monitoring

---

## Architecture

```
                        Browser
                           │
                    localhost:8080
                           │
               ┌───────────▼───────────┐
               │     Load Balancer      │
               │   Nginx (Round Robin)  │
               │    192.168.56.10       │
               └───────┬───────┬────────┘
                        │       │
           ┌────────────▼─┐   ┌─▼────────────┐
           │  App Server 1 │   │  App Server 2 │
           │  Nginx +      │   │  Nginx +      │
           │  Gunicorn +   │   │  Gunicorn +   │
           │  Django       │   │  Django       │
           │ 192.168.56.11 │   │ 192.168.56.13 │
           └──────┬────────┘   └────┬──────────┘
                  │                 │
                  └────────┬────────┘
                           │  TCP 3306
               ┌───────────▼───────────┐
               │      Database          │
               │    MySQL 8.0           │
               │    192.168.56.12       │
               └───────────────────────┘
```

### Network Configuration

| VM | Role | Private IP | Host Port |
|---|---|---|---|
| `lb` | Load Balancer | 192.168.56.10 | 8080 |
| `web` | App Server 1 | 192.168.56.11 | 8001 |
| `web2` | App Server 2 | 192.168.56.13 | 8002 |
| `db` | Database Server | 192.168.56.12 | — |

---

## Technology Stack

| Category | Technology | Purpose |
|---|---|---|
| Virtualization | VirtualBox + Vagrant | Local VM management and IaC |
| Operating System | Ubuntu 24.04 LTS | All virtual machines |
| Web Server | Nginx 1.24 | Reverse proxy and load balancer |
| Application Server | Gunicorn | WSGI server for Django |
| Web Framework | Django 6.0.5 | E-commerce application |
| Database | MySQL 8.0 | Relational data storage |
| Service Manager | Systemd | Gunicorn service management |
| Task Scheduler | Cron | Automated backup and monitoring |
| Version Control | Git + GitHub | Source code management |
| Scripting | Bash | Provisioning and automation scripts |
| Configuration | python-decouple | Environment variable management |
| Security | Firewall | for enhance the security on port |

---

## Infrastructure Details

### Load Balancer (lb VM)

- Nginx configured as a reverse proxy and load balancer
- Implements **Round Robin** algorithm to distribute traffic across both application servers
- Forwards request headers (`Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`) to preserve client information
- Monitors web server availability every 5 minutes via `lb_monitor.sh`

### Application Servers (web and web2 VMs)

- **Nginx** acts as a reverse proxy — forwards dynamic requests to Gunicorn via Unix socket
- **Gunicorn** runs 3 worker processes to handle concurrent requests
- **Django** application serves the ProShop e-commerce platform
- Static files served directly by Nginx from `staticfiles/` directory
- Media files served directly by Nginx from `media/` directory
- Gunicorn runs as a **Systemd service** with `Restart=always` for automatic recovery
- Server health monitored every 5 minutes via `monitor.sh`
- Automated database backup runs daily at 19:15 IST via `backup.sh`

### Database Server (db VM)

- MySQL 8.0 configured to accept remote connections from the private network
- Dedicated database user with privileges scoped to `proshop_db` only
- All credentials managed through environment variables — never hardcoded

---

## Prerequisites

Ensure the following are installed on your host machine before proceeding:

- [VirtualBox](https://www.virtualbox.org/) (7.x)
- [Vagrant](https://www.vagrantup.com/) (2.x)
- Git

---

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/Dheeraj-chelani/proshop.git
cd proshop
```

### 2. Clone the Infrastructure Repository

```bash
git clone https://github.com/Dheeraj-chelani/devops-vms.git
cd devops-vms/multivms
```

### 3. Configure Environment Variables

Before starting the VMs, create a secrets.env file and wirh this information
SECRET_KEY=<secret_key>
DB_USER=<username>
DB_PASSWORD=<password>

### 4. Start the Infrastructure

```bash
vagrant up
```

This single command will:

1. Create and boot all 4 virtual machines
2. Install all required packages on each VM
3. Clone the Django project from GitHub
4. Configure the virtual environment and install Python dependencies
5. Run Django migrations and collect static files
6. Import the latest database backup (if available in `backups/`)
7. Configure Nginx as a reverse proxy on both application servers
8. Configure Gunicorn as a Systemd service
9. Configure Nginx as a load balancer on the LB VM
10. Set up cron jobs for monitoring and backup

### 5. Access the Application

| URL | Description |
|---|---|
| `http://localhost:8080` | Application via Load Balancer |
| `http://localhost:8001` | Application via App Server 1 (direct) |
| `http://localhost:8002` | Application via App Server 2 (direct) |
| `http://localhost:8080/admin/` | Django Admin Panel |

> **Note:** Admin credentials are configured via the `.env` file during provisioning. Change the default admin password immediately after first login.

---

## Environment Configuration

All sensitive configuration is managed through a `.env` file which is **never committed to version control**.



### Generating a Django Secret Key

```bash
python3 -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"
```

> **Security Note:** The `.env` file is listed in `.gitignore` and must never be pushed to any repository.

---

## Project Structure

```
devops-vms/multivms/
├── Vagrantfile              # VM definitions and provisioning config
├── scripts/
│   ├── db.sh                # Database VM provisioning script
│   ├── web.sh               # App Server 1 provisioning script
│   ├── web2.sh              # App Server 2 provisioning script
│   ├── lb.sh                # Load Balancer provisioning script
│   ├── backup.sh            # Automated database backup script
│   ├── monitor.sh           # Application server health monitoring
│   ├── lb_monitor.sh        # Load balancer health monitoring
│   └── status.sh            # Live server status dashboard
└── backups/                 # Database backups (auto-generated, gitignored)
    └── proshop_YYYYMMDD_HHMMSS.sql.gz
```

---

## Scripts Overview

### `db.sh` — Database Provisioning

Installs and configures MySQL, creates the `proshop_db` database, creates the database user with appropriate privileges, and configures MySQL to accept remote connections from the private network.

### `web.sh` / `web2.sh` — Application Server Provisioning

Installs system dependencies, clones the Django project from GitHub, creates a Python virtual environment as the `vagrant` user, installs Python packages including Gunicorn, generates the `.env` configuration file, waits for the database to become available, runs Django migrations, collects static files, imports the latest database backup, configures Gunicorn as a Systemd service, configures Nginx as a reverse proxy, and sets up cron jobs for monitoring and backup.

### `lb.sh` — Load Balancer Provisioning

Installs Nginx and configures it as a load balancer with upstream servers pointing to both application servers using a round-robin algorithm.

### `backup.sh` — Database Backup

Runs daily at **19:15 IST** via cron. Reads database credentials securely from the environment, dumps the MySQL database, compresses it using gzip, saves it to the shared `/vagrant/backups/` directory, and removes backups older than 7 days.

```bash
# Run manually
sudo bash /vagrant/scripts/backup.sh

# View backup logs
cat /var/log/proshop_backup.log
```

### `monitor.sh` — Health Monitoring

Runs every **5 minutes** via cron on each application server. Checks CPU usage, RAM usage, disk usage, Nginx status, Gunicorn status, and database connectivity. Writes alerts to the log file when thresholds (80%) are exceeded.

```bash
# View monitoring logs
cat /var/log/proshop_monitor.log

# View only alerts
grep "ALERT" /var/log/proshop_monitor.log
```

### `lb_monitor.sh` — Load Balancer Monitoring

Runs every **5 minutes** via cron on the LB VM. Checks Nginx status and verifies HTTP 200 responses from both application servers.

```bash
# View LB monitoring logs
cat /var/log/lb_monitor.log
```

### `status.sh` — Live Status Dashboard

Run from the host machine to view the real-time status of all VMs in a single terminal output.

```bash
bash scripts/status.sh
```

Sample output:

```
=========================================
       PROSHOP SERVER STATUS
=========================================

--- WEB SERVER (192.168.56.11) ---
CPU: 23% | RAM: 45% | Disk: 34%
Nginx: active | Gunicorn: active

--- WEB2 SERVER (192.168.56.13) ---
CPU: 18% | RAM: 42% | Disk: 34%
Nginx: active | Gunicorn: active

--- DB SERVER (192.168.56.12) ---
CPU: 5% | RAM: 38% | Disk: 45%
MySQL: active

--- LOAD BALANCER (192.168.56.10) ---
CPU: 3% | RAM: 25% | Disk: 20%
Nginx: active

--- RECENT ALERTS ---
No alerts

=========================================
Last checked: Thu Jun 25 19:15:01 IST 2026
=========================================
```

---

## Monitoring & Backup

### Cron Schedule

| Script | Schedule | VM | Purpose |
|---|---|---|---|
| `monitor.sh` | Every 5 minutes | web, web2 | Server health check |
| `lb_monitor.sh` | Every 5 minutes | lb | LB and web server check |
| `backup.sh` | Daily at 19:15 IST | web | Database backup |

### Backup Location

Backups are stored in the shared `/vagrant/backups/` directory, which maps to `devops-vms/multivms/backups/` on the host machine. This ensures backups persist even if the VMs are destroyed.

### Restoring from Backup

```bash
# On the web VM
gunzip -c /vagrant/backups/proshop_YYYYMMDD_HHMMSS.sql.gz | \
    mysql -u <DB_USER> -p -h 192.168.56.12 proshop_db
```

---

## Troubleshooting

### 502 Bad Gateway

```bash
vagrant ssh web
sudo systemctl status gunicorn
sudo tail -20 /var/log/nginx/error.log
```

### Gunicorn Failed to Start

```bash
vagrant ssh web
journalctl -u gunicorn -n 30 --no-pager
```

### Database Connection Error

```bash
vagrant ssh web
mysql -u <DB_USER> -p -h 192.168.56.12 -e "use proshop_db;"
```

### Permission Denied on Socket

```bash
vagrant ssh web
sudo chown -R vagrant:www-data /home/vagrant/proshop
sudo chmod -R 775 /home/vagrant/proshop
sudo usermod -aG vagrant www-data
sudo systemctl restart nginx
```

### Static Files Not Loading

```bash
vagrant ssh web
cd /home/vagrant/proshop
source .venv/bin/activate
python manage.py collectstatic --noinput
sudo systemctl restart nginx
```

### VM Boot Timeout

```ruby
# In Vagrantfile:
config.vm.boot_timeout = 600
```

---

## Vagrant Commands Reference

```bash
vagrant up              # Start all VMs
vagrant up web          # Start a specific VM
vagrant halt            # Stop all VMs
vagrant destroy -f      # Destroy all VMs
vagrant ssh web         # SSH into a VM
vagrant provision web   # Re-run provisioning scripts
vagrant reload web      # Restart and reload Vagrantfile config
vagrant status          # View VM status
```

---

## Security Considerations

- All sensitive credentials are stored in `.env` files and excluded from version control via `.gitignore`
- Each service runs under a dedicated non-root user (`vagrant` for Gunicorn, `www-data` for Nginx, `mysql` for MySQL)
- Database access is restricted to a dedicated user with privileges scoped to `proshop_db` only
- CSRF protection is enforced via `CSRF_TRUSTED_ORIGINS` in Django settings
- `ALLOWED_HOSTS` is configured to prevent Host Header attacks
- No credentials are hardcoded in any script or configuration file committed to version control

---

## Future Scope

- **Docker + Docker Compose** — Containerize the application for lighter and faster deployments
- **Cloud Deployment** — Migrate to AWS EC2 + RDS for public accessibility
- **CI/CD Pipeline** — Implement GitHub Actions for automated testing and deployment
- **SSL/HTTPS** — Configure Let's Encrypt certificates for secure communication
- **Database Replication** — Add a MySQL replica to eliminate single point of failure
- **Ansible Automation** — Replace Bash provisioning scripts with Ansible playbooks
- **Centralized Logging** — Implement ELK Stack (Elasticsearch, Logstash, Kibana)
- **Grafana Dashboard** — Visual monitoring with Prometheus and Grafana

---

## Author

**Dheeraj Chelani**
B.Tech CSAI — 3rd Year


---


