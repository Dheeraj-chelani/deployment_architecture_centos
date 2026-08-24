# Ubuntu → CentOS Stream 9 Conversion Summary

## ⚠️ Before you run these — one prerequisite

Your Vagrantfile currently uses `bento/ubuntu-24.04` boxes. For these scripts
to work, change your VM boxes to a CentOS Stream 9 box, e.g.:

```ruby
config.vm.box = "bento/centos-stream-9"
# or
config.vm.box = "generic/centos9s"
```

Everything below assumes the guest OS is already CentOS Stream 9.

---

## The 3 recurring themes across every script

1. **`apt` → `dnf`**, with several package names changed.
2. **SELinux** — enforcing by default on CentOS/RHEL (Ubuntu has none). This
   is the single biggest source of "it worked on Ubuntu but not here" bugs.
3. **`firewalld`** — running by default on CentOS/RHEL (Ubuntu's script had
   no active firewall at all). Every port your app needs must be explicitly
   opened.

---

## db.sh
| Change | Reason |
|---|---|
| `apt-get` → `dnf` | Package manager |
| Service name `mysql` → `mysqld` | RHEL names the MySQL systemd unit differently |
| Config path `/etc/mysql/mysql.conf.d/mysqld.cnf` → `/etc/my.cnf.d/mysql-server.cnf` | Different file layout |
| `bind-address` fix made idempotent (check-then-append) | RHEL's default config often lacks this line entirely; blind `sed` would silently no-op |
| Added `firewall-cmd --add-port=3306/tcp` | firewalld blocks remote DB connections by default on CentOS |

## lb.sh
| Change | Reason |
|---|---|
| `apt-get` → `dnf` | Package manager |
| Config written to `/etc/nginx/conf.d/loadbalancer.conf` instead of `sites-available`/`sites-enabled` | RHEL's nginx package has no such convention — conf.d is auto-included |
| Added `listen 80 default_server;` | RHEL's stock `nginx.conf` ships its own built-in server block; this forces our config to win |
| Added `setsebool -P httpd_can_network_connect on` | SELinux blocks nginx's outbound `proxy_pass` to other VMs unless explicitly allowed — this is why load balancing would silently 502 without this line |
| Added `firewall-cmd --add-port=80/tcp` | Port 80 blocked by default otherwise |
| Added install of `cronie` + `systemctl enable --now crond` | Cron isn't guaranteed pre-installed/running on a minimal CentOS box |

## web.sh / web2.sh
| Change | Reason |
|---|---|
| `apt-get` → `dnf` | Package manager |
| `python3-venv` removed | venv module ships inside `python3` on RHEL9 already |
| `mysql-client` → `mysql` | Client package renamed |
| `libmysqlclient-dev` → `mysql-devel` | Dev headers package renamed |
| `pkg-config` → `pkgconfig` | Package renamed |
| `python3-dev` → `python3-devel` | Package renamed |
| Added `gcc` | Needed to compile the `mysqlclient` C extension — Ubuntu's box had build tools already present so it wasn't listed there originally |
| Added `policycoreutils-python-utils`, `firewalld`, `cronie` | Needed for `semanage`/SELinux, firewall, and cron respectively |
| Nginx config moved to `/etc/nginx/conf.d/proshop.conf` | No sites-available/enabled convention on RHEL |
| Added `listen 80 default_server;` | Same reasoning as lb.sh |
| `Group=www-data` → `Group=nginx` in the Gunicorn systemd unit | `www-data` doesn't exist on RHEL; nginx runs as user/group `nginx` |
| `chown ... www-data` → `chown ... nginx`, `usermod -aG vagrant www-data` → `usermod -aG vagrant nginx` | Same reason |
| **Added `semanage fcontext` + `restorecon`** on `/home/vagrant/proshop` | **Most important change.** SELinux labels home directories `user_home_t` by default — nginx's process type (`httpd_t`) can never read that label, regardless of correct Linux permissions. Without this you'd get "13: Permission denied" again, but this time `chmod`/`chown` alone won't fix it |
| Added a second `restorecon` after starting Gunicorn | The freshly-created `gunicorn.sock` file doesn't always auto-inherit the directory's SELinux context; relabeling once more after it exists is the safe fix |
| Added `firewall-cmd --add-port=80/tcp` | Port 80 blocked by default otherwise |

## monitor.sh
No changes required. `top`, `free`, `df`, `systemctl`, and the `mysql` client
command behave identically on both distros — this script only ever talks to
services by their already-correct names (`nginx`, `gunicorn`) or connects to
MySQL as a remote client, so the `mysql`-vs-`mysqld` service-name difference
doesn't apply here.

## lb_monitor.sh
No changes required, same reasoning as monitor.sh. `curl` is explicitly
installed via `dnf` in `lb.sh` to guarantee it's present.

## backup.sh
No changes required. `mysqldump` ships inside the same `mysql` client
package installed via `dnf` in web.sh, with identical flags/behaviour to
Ubuntu's `mysql-client`. The `/vagrant` shared folder is a VirtualBox
feature, not an OS one, so it's unaffected either way.

## status.sh
Runs on your **host** laptop (still Ubuntu), so almost nothing changed.
| Change | Reason |
|---|---|
| `systemctl is-active mysql` → `systemctl is-active mysqld` (DB VM check only) | The remote guest's service is now literally named `mysqld` |

---

## Quick pre-flight checklist before your first `vagrant up`

- [ ] Vagrantfile boxes changed to a CentOS Stream 9 box
- [ ] Enough RAM allocated — SELinux + firewalld + dnf add a small overhead vs. Ubuntu minimal
- [ ] After first provision, always check `sudo ausearch -m avc -ts recent` if something is denied unexpectedly — this is CentOS/RHEL's equivalent of "check the SELinux audit log," the fastest way to diagnose a silent permission failure that isn't a normal Linux permission issue
