# 🐳 Local Development Stack

> Zero-configuration local development environment - Windows, Linux, macOS compatible

## ✨ Features

- 🚀 **One-command setup**: `docker-compose up -d`
- 🔒 **Automatic SSL**: Self-signed certificates for local development
- 🌐 **Auto domains**: `/projects/myapp` → `https://myapp.localhost`
- � **Full automation**: Continuous monitoring and auto-configuration
- 🔍 **Smart detection**: Automatically detects Laravel or standard websites
- 🧹 **Auto cleanup**: Removes configurations for deleted projects
- 🗂️ **Multi-project**: Unlimited project support
- 🛠️ **PHP 8.3 + MySQL 8.0 + Redis + Nginx**

## 🎯 Quick Start

### 1. Clone
```bash
git clone https://github.com/yourusername/docker-dev-stack.git
cd docker-dev-stack
```

### 2. Start (that's it!)
```bash
docker-compose up -d
```

### 3. Add your project
```bash
# Create project folder
mkdir -p projects/myapp
echo "<?php echo 'Hello World!'; ?>" > projects/myapp/index.php
```

### 4. Open in browser
```
https://myapp.localhost
```

**🔒 First time SSL setup:**
- First visit will show "Not secure" warning
- Click "Advanced" → "Proceed to myapp.localhost (unsafe)"
- Certificate will be permanently accepted
- All future .localhost domains will work without warnings!

*This is normal for local development - we use self-signed certificates that are perfectly secure for local use.*

## 🎮 Commands

```bash
docker-compose up -d      # Start all services
docker-compose down       # Stop all services  
docker-compose restart    # Restart all services
docker-compose ps         # Show service status
docker-compose logs -f    # Show service logs
```

> **Note:** The system works completely automatically! All projects are monitored and configured without manual intervention.

## 📁 Directory Structure

```
docker-dev-stack/
├── projects/              # Put your projects here
│   ├── myapp/            → https://myapp.localhost
│   ├── api-project/      → https://api-project.localhost
│   └── blog/             → https://blog.localhost
├── docker-compose.yml    # Main configuration
├── .env                  # Settings (optional)
└── docker/              # Container configurations
```

## 📱 Subdomain Usage

Create `subdomains.json` in any project to add subdomains:

```json
{
  "subdomains": [
    {
      "subdomain": "api",
      "folder": "api"
    },
    {
      "subdomain": "www", 
      "folder": null
    }
  ]
}
```

## ⚙️ Services

- **Web Server**: Nginx (80, 443)
- **PHP**: PHP 8.3-FPM (containerized)
- **Database**: MySQL 8.0 (3306)
- **Cache**: Redis (6379)
- **Admin**: phpMyAdmin (8080)

## 🔧 Configuration

### Environment Variables (.env)
```bash
# Project folder (default: ./projects)
PROJECTS_PATH=/path/to/your/projects

# Domain suffix (default: .localhost)
DOMAIN_SUFFIX=.localhost

# MySQL root password
MYSQL_ROOT_PASSWORD=root
```

*Create a `.env` file to customize the path to your projects. The watcher will automatically detect folders created in this path.*

## 📋 Requirements

- Docker
- Docker Compose

That's it! 🎉

## 🆘 Troubleshooting

### SSL "Not Secure" Warning
**This is normal for local development!** 

**First time setup (do once per browser):**
1. Visit any `.localhost` site (e.g., `https://test-project.localhost`)
2. Click "Advanced" or "Not secure" 
3. Click "Proceed to [domain] (unsafe)" or "Continue to site"
4. ✅ Done! All future `.localhost` domains will work without warnings

**Why this happens:** We use self-signed certificates which are perfectly secure for local development, but browsers show warnings until you accept them once.

### Project Not Visible
If a project is not automatically detected or configured:
```bash
# Simply restart the container
docker-compose restart file_watcher

# Or check logs for any issues
docker-compose logs -f file_watcher
```

> **Note:** The system runs periodic scans every 10 seconds to detect any missing configurations. Manual commands are rarely needed!

### Changing Project Directory
```bash
# Stop services
docker-compose down

# Create .env file
echo "PROJECTS_PATH=/path/to/your/projects" > .env

# Start again
docker-compose up -d
```

The system will automatically detect and configure all projects in the new path!

## 🤝 Contributing

1. Fork it
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## 📝 License

MIT License - see [LICENSE](LICENSE) file for details.

## ⭐ Star the Project

If you like this project, don't forget to give it a star! ⭐

---

**Made with ❤️ for developers who want zero-config local development**
