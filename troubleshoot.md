# ProShop Infrastructure — Troubleshooting Guide

This document catalogs the real issues encountered while designing, provisioning, and automating a multi-tier Vagrant infrastructure (Nginx Load Balancer → Web Servers → MySQL) for the ProShop Django application, along with the root cause and exact fix for each. It is intended as both a debugging reference and a record of the reasoning behind key infrastructure decisions.

## Table of Contents

**Django Configuration**
- [1. `ImproperlyConfigured: STATIC_ROOT` not set](#1-improperlyconfigured-static_root-not-set)
- [2. `CommandError: ALLOWED_HOSTS` required when `DEBUG=False`](#2-commanderror-allowed_hosts-required-when-debugfalse)
- [3. Product images not loading with `DEBUG=False`](#3-product-images-not-loading-with-debugfalse)

**Gunicorn / systemd**
- [4. Gunicorn service fails with `status=203/EXEC`](#4-gunicorn-service-fails-with-status203exec)
- [5. Gunicorn service fails with `ModuleNotFoundError`](#5-gunicorn-service-fails-with-modulenotfounderror)

**Nginx & Networking**
- [6. Browser shows `NS_ERROR_NET_EMPTY_RESPONSE`](#6-browser-shows-ns_error_net_empty_response)
- [7. Nginx serves the default "Welcome to nginx!" page](#7-nginx-serves-the-default-welcome-to-nginx-page)
- [8. `502 Bad Gateway` — server_name / socket path mismatch](#8-502-bad-gateway--server_name--socket-path-mismatch)
- [9. `502 Bad Gateway` — Permission denied on Unix socket (Ubuntu)](#9-502-bad-gateway--permission-denied-on-unix-socket-ubuntu)
- [10. Static files return `404` despite `collectstatic` succeeding](#10-static-files-return-404-despite-collectstatic-succeeding)

**Data & Database**
- [11. Storefront loads but shows zero products](#11-storefront-loads-but-shows-zero-products)
- [12. `vagrant scp` command not found](#12-vagrant-scp-command-not-found)
- [13. Django admin login fails with correct-looking credentials](#13-django-admin-login-fails-with-correct-looking-credentials)

**Automation & Provisioning**
- [14. Cron job silently missing after provisioning](#14-cron-job-silently-missing-after-provisioning)
- [15. `memcached` fails with `bind(): Cannot assign requested address`](#15-memcached-fails-with-bind-cannot-assign-requested-address)

**Ubuntu → CentOS Stream 9 Migration**
- [16. `dnf module enable mysql:8.4` fails / breaks provisioning](#16-dnf-module-enable-mysql84-fails--breaks-provisioning)
- [17. `502 Bad Gateway` on CentOS despite correct socket permissions](#17-502-bad-gateway-on-centos-despite-correct-socket-permissions)
- [18. Nginx logs `conflicting server name "_" on 0.0.0.0:80`](#18-nginx-logs-conflicting-server-name--on-0000080)
- [19. `msmtp: No match for argument: msmtp`](#19-msmtp-no-match-for-argument-msmtp)
- [20. `msmtp: account default not found: no configuration file available`](#20-msmtp-account-default-not-found-no-configuration-file-available)

---

## 1. `ImproperlyConfigured: STATIC_ROOT` not set

### Issue / Error Description
Running `python manage.py collectstatic` failed with:
```
django.core.exceptions.ImproperlyConfigured: You're using the staticfiles app 
without having set the STATIC_ROOT setting to a filesystem path.
```

### Root Cause
`STATIC_ROOT` is the single destination folder Django uses to gather static assets from all apps (`store/static/`, the Django admin's built-in static files, etc.) into one place, so Nginx can serve them directly without going through Django/Gunicorn at all. This setting was missing from `settings.py`.

### Resolution
Add the setting in `settings.py`:
```python
STATIC_ROOT = BASE_DIR / 'staticfiles'
```
Then re-run:
```bash
python manage.py collectstatic
```

### Prevention
Add `STATIC_ROOT` to the Django project template from the start of any deployment-bound project — it's easy to miss locally since `runserver` doesn't require it at all.

---

## 2. `CommandError: ALLOWED_HOSTS` required when `DEBUG=False`

### Issue / Error Description
After setting `DEBUG=False` for a production-style test, starting the server threw:
```
CommandError: You must set settings.ALLOWED_HOSTS if DEBUG is False.
```

### Root Cause
Django's security model requires an explicit host allowlist once `DEBUG` is off, to prevent HTTP Host header attacks. `ALLOWED_HOSTS` was left as an empty list (the default).

### Resolution
Add to `.env`:
```
ALLOWED_HOSTS=localhost,127.0.0.1,192.168.56.11
```
Parse it in `settings.py` using `python-decouple`:
```python
ALLOWED_HOSTS = config(
    'ALLOWED_HOSTS',
    cast=lambda v: [s.strip() for s in v.split(',')]
)
```

### Prevention
Keep `ALLOWED_HOSTS` environment-driven from day one rather than hardcoding it, so each environment (local, VM, production) can define its own list without a code change.

---

## 3. Product images not loading with `DEBUG=False`

### Issue / Error Description
With `DEBUG=False`, the storefront rendered correctly but all product images were broken.

### Root Cause
Django's development server only serves user-uploaded media files (`MEDIA_URL`/`MEDIA_ROOT`) automatically when `DEBUG=True`. With `DEBUG=False`, Django expects a real web server (Nginx, in this project) to serve media files — it stops doing so itself.

### Resolution
For local testing, temporarily set `DEBUG=True` in `.env`. In the actual VM deployment, this is resolved permanently by having Nginx serve `/media/` directly:
```nginx
location /media/ {
    root /home/vagrant/proshop;
}
```

### Prevention
Treat `DEBUG=True` as a local-only convenience flag, never a deployment setting — and make sure the reverse proxy config for `/media/` is in place *before* flipping `DEBUG` to `False` anywhere.

---

## 4. Gunicorn service fails with `status=203/EXEC`

### Issue / Error Description
```
sudo systemctl status gunicorn
Active: failed (Result: exit-code)
Main PID: ... (code=exited, status=203/EXEC)
```

### Root Cause
`status=203/EXEC` means systemd could not find or execute the binary specified in `ExecStart`. The service file initially pointed to a nested, incorrect path (`.../proshop/proshop/.venv/bin/gunicorn`) instead of the virtual environment's actual location.

### Resolution
Verify the real path first:
```bash
ls /home/vagrant/proshop/.venv/bin/gunicorn
```
Then correct `ExecStart` in `/etc/systemd/system/gunicorn.service` to match exactly, and reload:
```bash
sudo systemctl daemon-reload
sudo systemctl restart gunicorn
```

### Prevention
Always confirm a binary's actual path with `which` or `ls` before writing it into a systemd unit — never assume the path based on project structure alone.

---

## 5. Gunicorn service fails with `ModuleNotFoundError`

### Issue / Error Description
After fixing the path above by pointing to the system-wide `/usr/bin/gunicorn`, the service failed again:
```
ModuleNotFoundError: No module named 'django'
```

### Root Cause
Django and all other project dependencies were installed **only inside the project's virtual environment** (`.venv`), not system-wide. Running the system Gunicorn binary meant it was using the system Python interpreter, which had no access to those packages.

### Resolution
Point `ExecStart` specifically to the virtual environment's Gunicorn binary, not the system one:
```ini
ExecStart=/home/vagrant/proshop/.venv/bin/gunicorn \
          --workers 3 \
          --bind unix:/home/vagrant/proshop/gunicorn.sock \
          proshop.wsgi:application
```

### Prevention
When a project uses a virtual environment, every process that depends on that project (Gunicorn included) must be launched using the venv's own interpreter/binaries — never the system-wide equivalent.

---

## 6. Browser shows `NS_ERROR_NET_EMPTY_RESPONSE`

### Issue / Error Description
Visiting `http://localhost:8001` returned an empty response with no page rendering at all.

### Root Cause
The Vagrantfile's port-forwarding rule forwarded guest port `8000` to the host, but Nginx inside the VM was actually listening on port `80`. The forwarded port simply had nothing listening on the other end.

### Resolution
Correct the Vagrantfile:
```ruby
web.vm.network "forwarded_port", guest: 80, host: 8001
```
Then reload the VM:
```bash
vagrant reload web
```

### Prevention
Always match the `guest:` port in a forwarded-port rule to whatever port the service *inside* the VM is actually bound to — not the port used during initial local development.

---

## 7. Nginx serves the default "Welcome to nginx!" page

### Issue / Error Description
After fixing the port-forwarding issue above, the browser now showed Nginx's stock welcome page instead of the Django application.

### Root Cause
Ubuntu's Nginx package ships a default site config, enabled via a symlink in `/etc/nginx/sites-enabled/default`. Since this default config was never removed, Nginx matched it before the custom ProShop config.

### Resolution
```bash
sudo rm /etc/nginx/sites-enabled/default
sudo systemctl restart nginx
```

### Prevention
Always explicitly remove or disable the distro's default site config as a standard step whenever adding a custom Nginx server block.

---

## 8. `502 Bad Gateway` — server_name / socket path mismatch

### Issue / Error Description
After removing the default site, Nginx returned `502 Bad Gateway`.

### Root Cause
Two separate issues compounded here:
1. `server_name` in the Nginx config was set to a specific IP (`192.168.56.11`), but the browser was sending requests with `Host: localhost:8001`, causing a mismatch.
2. A VM reload had regenerated the Gunicorn socket, and the Nginx config was pointing to a stale/incorrect socket path (an extra nested `proshop/proshop/` in the path).

### Resolution
Set a wildcard server name to accept any host header:
```nginx
server_name _;
```
And correct the socket path to match reality exactly:
```nginx
proxy_pass http://unix:/home/vagrant/proshop/gunicorn.sock;
```

### Prevention
Use `server_name _;` for internal/testing environments where the exact request host isn't guaranteed. After any VM reload, verify the actual socket path with `ls -la` rather than assuming it's unchanged.

---

## 9. `502 Bad Gateway` — Permission denied on Unix socket (Ubuntu)

### Issue / Error Description
Nginx error log showed:
```
connect() to unix:/home/vagrant/proshop/gunicorn.sock failed 
(13: Permission denied) while connecting to upstream
```

### Root Cause
Gunicorn (running as user `vagrant`) created the socket file owned by `vagrant:www-data`. Nginx runs as user `www-data`, which was not a member of the `vagrant` group and therefore lacked permission to connect to the socket, despite the socket's own file permissions looking correct.

### Resolution
```bash
sudo usermod -aG vagrant www-data
sudo systemctl restart nginx
sudo systemctl restart gunicorn
```

### Prevention
When two services from different system users need to communicate via a Unix socket, plan the group membership explicitly as part of the provisioning script — don't rely on default permissions.

---

## 10. Static files return `404` despite `collectstatic` succeeding

### Issue / Error Description
CSS/JS assets (including the unstyled Django admin panel) returned `404`, even though `collectstatic` had copied 222 files successfully.

### Root Cause
The Nginx config used the `root` directive for the `/static/` location, but `root` appends the URL path to the given directory. Since the actual folder was named `staticfiles` (not `static`), the resulting path Nginx looked for (`.../static/...`) never matched the real folder (`.../staticfiles/...`).

### Resolution
Use `alias` instead of `root`, which maps the location directly to the folder without appending the URL path:
```nginx
location /static/ {
    alias /home/vagrant/proshop/staticfiles/;
}
```

### Prevention
Remember the key distinction: `root` appends the request URI to the path; `alias` replaces the matched location with the given path exactly. Use `alias` whenever the on-disk folder name doesn't match the URL prefix.

---

## 11. Storefront loads but shows zero products

### Issue / Error Description
The site rendered correctly, static assets loaded, but no products or images appeared anywhere on the storefront.

### Root Cause
Product **images** existed on the VM (cloned via Git), but the **database** itself had zero product records — Git doesn't carry database contents, and a fresh `migrate` only creates empty tables. Django renders the storefront from database queries, not from the presence of media files alone.

### Resolution
Export data from the source MySQL instance:
```bash
mysqldump -u harry -ppassword proshop_db > proshop_data.sql
```
Transfer it to the VM and import:
```bash
mysql -u harry -ppassword -h 192.168.56.12 proshop_db < proshop_data.sql
```

### Prevention
Treat database seeding as a distinct deployment step from code deployment — never assume that cloning a repository also populates its database.

---

## 12. `vagrant scp` command not found

### Issue / Error Description
```
vagrant scp ~/Desktop/proshop_data.sql web:/home/vagrant/proshop_data.sql
Usage: vagrant [options] <command> [<args>]
```

### Root Cause
`vagrant scp` is not a built-in Vagrant command — it requires the separate `vagrant-scp` plugin, which was not installed.

### Resolution
Used the built-in `vagrant upload` command instead, which ships with Vagrant by default and requires no plugin:
```bash
vagrant upload ~/Desktop/proshop_data.sql /home/vagrant/proshop_data.sql web
```

### Prevention
Prefer Vagrant's built-in commands (`vagrant upload`) over plugin-dependent ones where possible, to keep the environment reproducible without extra plugin installation steps.

---

## 13. Django admin login fails with correct-looking credentials

### Issue / Error Description
A website-registered user could not log into `/admin/`, despite entering what appeared to be the correct username and password.

### Root Cause
Two distinct sub-issues surfaced here:
1. A regular registered user account is not automatically admin-eligible — it requires `is_staff=True` (and typically `is_superuser=True`) to access `/admin/` at all.
2. Separately, a *superuser* account (`dheeraj`) that was created directly on the VM had a different password set on the VM than what was assumed locally.

### Resolution
Verify user flags via the Django shell:
```bash
python manage.py shell -c \
  "from django.contrib.auth.models import User; \
   print(list(User.objects.values('username','is_staff','is_superuser')))"
```
Reset the password directly if needed:
```bash
python manage.py changepassword <username>
```

### Prevention
Keep a clear mental (and documented) separation between "website users" and "admin/staff users" — they are governed by different flags, not just different login forms.

---

## 14. Cron job silently missing after provisioning

### Issue / Error Description
After provisioning, only the `backup.sh` cron entry was present; the `monitor.sh` entry was missing entirely, with no error shown during provisioning.

### Root Cause
The provisioning script used `set -e`, and `crontab -l` returns a non-zero exit code the very first time it's run on a VM with no existing crontab (even with `2>/dev/null` suppressing the error message, the exit code itself still propagates). Under `set -e`, that non-zero exit silently terminated the subshell before the `echo` for the first cron line could run — so only the *second* cron-adding command (which by then found an existing, non-empty crontab and succeeded) took effect.

### Resolution
Append `|| true` to neutralize the exit code from the expected-to-fail first read:
```bash
(crontab -l 2>/dev/null || true; echo "*/5 * * * * ...") | crontab -
```

### Prevention
Whenever combining `set -e` with a command that is *expected* to fail under normal conditions (like reading a not-yet-existing crontab), explicitly handle that expected failure with `|| true` rather than assuming `2>/dev/null` alone is sufficient.

---

## 15. `memcached` fails with `bind(): Cannot assign requested address`

### Issue / Error Description
```
memcached[...]: bind(): Cannot assign requested address
failed to listen on TCP port 11211: Cannot assign requested address
```

### Root Cause
The configuration's `OPTIONS` line still contained `::1` (IPv6 localhost) alongside the corrected IPv4 `0.0.0.0` binding. The environment could not bind to `::1` as configured, causing memcached to fail entirely rather than partially succeed.

### Resolution
Simplify the bind option to IPv4 only:
```bash
sed -i 's/OPTIONS=.*/OPTIONS="-l 0.0.0.0"/' /etc/sysconfig/memcached
systemctl restart memcached
```

### Prevention
When changing a bind address, check the *entire* options string for other conflicting address entries (like a leftover IPv6 binding) rather than assuming a single find-and-replace covers every case.

---

## 16. `dnf module enable mysql:8.4` fails / breaks provisioning

### Issue / Error Description
Adding `dnf module enable mysql:8.4 -y` after `mysql` was already installed caused the provisioning script to fail outright (and, under `set -e`, abort the rest of the script).

### Root Cause
DNF's module system does not allow switching a package's module stream after it has already been installed from a different stream (the default `mysql:8.0` stream, in this case) without first removing it. Attempting to enable a different stream post-install simply errors out.

### Resolution
Remove the stream-switch command entirely and rely on the default stream consistently across all VMs:
```bash
dnf install -y mysql mysql-devel pkgconfig \
    policycoreutils-python-utils firewalld cronie curl
```

### Prevention
Decide on a module stream (or accept the distro default) *before* the first install, and keep it consistent across every VM that needs the same package — module-stream mismatches between client and server are also a source of subtle version-compatibility bugs.

---

## 17. `502 Bad Gateway` on CentOS despite correct socket permissions

### Issue / Error Description
On CentOS Stream 9, Nginx returned `502 Bad Gateway` with:
```
connect() to unix:/home/vagrant/proshop/gunicorn.sock failed 
(13: Permission denied)
```
— even though the socket file itself showed `srwxrwxrwx` permissions and SELinux was confirmed to be in `Permissive` mode (ruling it out as the cause).

### Root Cause
CentOS/RHEL's default permission on `/home/vagrant` itself is `700` (Ubuntu defaults to `755`). This meant no user other than `vagrant` could even *traverse into* the home directory — regardless of how permissive the socket file's own permissions were, Nginx (running as `nginx`) was blocked at the parent directory level before it ever reached the socket.

### Resolution
Diagnose with:
```bash
namei -l /home/vagrant/proshop/gunicorn.sock
```
Grant the group (which `nginx` had already been added to) traversal rights on the home directory:
```bash
chmod g+x /home/vagrant
sudo systemctl restart nginx
```

### Prevention
When debugging Unix-socket permission errors, always check the traversal (`x`) permission on *every parent directory* in the path with `namei -l`, not just the target file itself — this is especially important on RHEL-family distros, whose default home-directory permissions are stricter than Debian-family distros.

---

## 18. Nginx logs `conflicting server name "_" on 0.0.0.0:80`

### Issue / Error Description
Nginx's error log showed a recurring warning:
```
conflicting server name "_" on 0.0.0.0:80, ignored
```

### Root Cause
Unlike Ubuntu's Nginx package, RHEL/CentOS's stock `/etc/nginx/nginx.conf` ships with its own built-in `server {}` block using the same catch-all `server_name _;`. Adding a custom config under `/etc/nginx/conf.d/` with the same server name on the same port creates a naming conflict Nginx flags (though it does not necessarily prevent the correct block from serving, if marked `default_server`).

### Resolution
Explicitly mark the custom config's `listen` directive as the default for that port, which takes priority regardless of the conflict warning:
```nginx
listen 80 default_server;
```

### Prevention
When moving Nginx configuration from Debian/Ubuntu to RHEL/CentOS, always check the stock `nginx.conf` for a pre-existing built-in server block before assuming a clean slate — this is a common cross-distro migration gotcha.

---

## 19. `msmtp: No match for argument: msmtp`

### Issue / Error Description
```
sudo dnf install -y msmtp
No match for argument: msmtp
Error: Unable to find a match: msmtp
```

### Root Cause
`msmtp` is not part of CentOS Stream 9's default BaseOS/AppStream repositories — it is only available via the EPEL (Extra Packages for Enterprise Linux) repository, which was not yet enabled.

### Resolution
```bash
sudo dnf install -y epel-release
sudo dnf makecache
sudo dnf install -y msmtp
```

### Prevention
When a package "doesn't exist" on a RHEL-family system but is known to exist generally, check whether it requires EPEL before assuming it's unavailable outright.

---

## 20. `msmtp: account default not found: no configuration file available`

### Issue / Error Description
```
echo "Test email" | msmtp someone@gmail.com
msmtp: account default not found: no configuration file available
```

### Root Cause
Two separate issues were involved:
1. The `/etc/msmtprc` config file had been created with `sudo` and then locked down with `chmod 600`, meaning only the `root` user could read it — but the test command was run as the unprivileged `vagrant` user, which could not see the file's contents at all.
2. Separately, a typo in the config (`gmial.com` instead of `gmail.com`) would have caused authentication to fail even once the permission issue was resolved.

### Resolution
Run mail-sending commands as root (matching how cron jobs actually execute them in production):
```bash
sudo bash -c 'echo "Test email" | msmtp someone@gmail.com'
```
And carefully verify the domain spelling in `/etc/msmtprc`.

### Prevention
Keep credential files like `/etc/msmtprc` restricted to `600`/root-only as a deliberate security choice — but always test as the same user (or via `sudo`) that will actually run the command in production (e.g., cron, which runs as root), rather than as your interactive shell user.

---

## Related Documents
- [README.md](./README.md) — project overview, architecture, and setup instructions
- [SUMMARY.md](./SUMMARY.md) — full list of Ubuntu → CentOS Stream 9 migration changes
