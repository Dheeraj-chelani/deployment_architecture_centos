# CHANGED: removed the 'dotenv' gem / vagrant-dotenv plugin entirely.
# The gem that plugin pulls in (dotenv 0.11.1) is old and calls
# File.exists?, a method Ruby removed in newer versions — which is exactly
# the "NoMethodError: undefined method `exists?'" you just hit. Rather than
# fighting gem/plugin version mismatches, we just parse secrets.env
# ourselves with a few lines of plain Ruby. No external dependency, so this
# can never break due to a gem update again.
#
# Uses an absolute path (File.join(__dir__, ...)) so it works no matter
# which directory you run `vagrant up` from.
secrets_file = File.join(__dir__, 'secrets.env')

unless File.exist?(secrets_file)
  raise "secrets.env not found at #{secrets_file}! Create it next to this Vagrantfile."
end

File.readlines(secrets_file).each do |line|
  line = line.strip
  next if line.empty? || line.start_with?('#')   # skip blank lines/comments

  key, value = line.split('=', 2)
  next if key.nil? || value.nil?

  # Strip matching surrounding quotes if present, e.g. KEY='value' or KEY="value"
  value = value.strip.gsub(/\A(['"])(.*)\1\z/, '\2')

  # ENV[]= always overrides, so this behaves like Dotenv.overload did
  ENV[key.strip] = value
end

# ADDED: fail-fast validation. If any secret is missing/empty, stop right
# here on your laptop with a clear message — instead of finding out deep
# inside a VM via a confusing MySQL "Access denied" error after provisioning
# has already run.
["SECRET_KEY", "DB_USER", "DB_PASSWORD", "GMAIL", "GMAIL_PASSWORD"].each do |key|
  if ENV[key].nil? || ENV[key].strip.empty?
    raise "#{key} is empty or missing! Check that secrets.env exists next to this Vagrantfile and contains #{key}=..."
  end
end

Vagrant.configure("2") do |config|
  # config.vm.synced_folder ".", "/vagrant", type: "nfs"

  # 1. DATABASE SERVER
  config.vm.define "db" do |db|
    db.vm.box = "eurolinux-vagrant/centos-stream-9"
    db.vm.hostname = "db-server"
    db.vm.network "private_network", ip: "192.168.56.12"
    db.vm.provider "virtualbox" do |vb|
      vb.memory = "512"
      vb.cpus = 1
    end
    db.vm.provision "shell",
      path: "scripts/db.sh",
      env: {
        "DB_USER"     => ENV["DB_USER"],
        "DB_PASSWORD" => ENV["DB_PASSWORD"],
        "GMAIL"         => ENV["GMAIL"],
        "GMAIL_PASSWORD" => ENV["GMAIL_PASSWORD"]
      }
  end

  # 2. WEB SERVER 1
  config.vm.define "web" do |web|
    web.vm.box = "eurolinux-vagrant/centos-stream-9"
    web.vm.hostname = "web-server"
    web.vm.network "private_network", ip: "192.168.56.11"
    web.vm.network "forwarded_port", guest: 80, host: 8001
    web.vm.provider "virtualbox" do |vb|
      vb.memory = "512"
      vb.cpus = 1
    end
    web.vm.provision "shell",
      path: "scripts/web.sh",
      env: {
        "SECRET_KEY"  => ENV["SECRET_KEY"],
        "DB_USER"     => ENV["DB_USER"],
        "DB_PASSWORD" => ENV["DB_PASSWORD"],
        "GMAIL"       => ENV["GMAIL"],
        "GMAIL_PASSWORD" => ENV["GMAIL_PASSWORD"]
      }
  end

  # 3. WEB SERVER 2
  config.vm.define "web2" do |web2|
    web2.vm.box = "eurolinux-vagrant/centos-stream-9"
    web2.vm.hostname = "web2-server"
    web2.vm.network "private_network", ip: "192.168.56.13"
    web2.vm.network "forwarded_port", guest: 80, host: 8002
    web2.vm.provider "virtualbox" do |vb|
      vb.memory = "512"
      vb.cpus = 1
    end
    web2.vm.provision "shell",
      path: "scripts/web2.sh",
      env: {
        "SECRET_KEY"  => ENV["SECRET_KEY"],
        "DB_USER"     => ENV["DB_USER"],
        "DB_PASSWORD" => ENV["DB_PASSWORD"],
        "GMAIL"       => ENV["GMAIL"],
        "GMAIL_PASSWORD" => ENV["GMAIL_PASSWORD"]
      }
  end

  # 4. LOAD BALANCER
  config.vm.define "lb" do |lb|
    lb.vm.box = "eurolinux-vagrant/centos-stream-9"
    lb.vm.hostname = "load-balancer"
    lb.vm.network "private_network", ip: "192.168.56.10"
    lb.vm.network "forwarded_port", guest: 80, host: 8080
    lb.vm.provider "virtualbox" do |vb|
      vb.memory = "512"
      vb.cpus = 1
    end
    lb.vm.provision "shell",
      path: "scripts/lb.sh",
      env: {
        "GMAIL"       => ENV["GMAIL"],
        "GMAIL_PASSWORD" => ENV["GMAIL_PASSWORD"]
      }
  end

end