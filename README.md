# ![PowerShell Logo](https://raw.githubusercontent.com/PowerShell/PowerShell/master/assets/Powershell_256.png) PowerShell Scripts Collection

Welcome to the **PowerShell Scripts Collection**!  
This repository is a curated set of PowerShell scripts designed to automate, troubleshoot, and manage a variety of IT and cloud administration tasks. Whether you're working with Active Directory, Azure, DFSR, IIS, or general system diagnostics, you'll find useful tools here to make your job easier.

---

## 📂 What's Inside?

- **Active Directory**: User password info, account lockout source, and more.
- **Azure**: Resource group creation, VM deployment, app registration, and migration scripts.
- **DFSR**: Backlog, conflict size, and state reporting.
- **IIS**: App pool and site management.
- **System Utilities**: Disk size, uptime, HBA info, port testing, and more.

Explore the [Azure](Azure/) and [System Center](System%20Center/) folders for specialized automation!

---

## 🚀 Getting Started

1. **Clone the repository**  
   ```sh
   git clone https://github.com/andystumph/PowerShell.git
   cd PowerShell
   ```

2. **Run a script**  
   Open your favorite PowerShell terminal and execute:
   ```sh
   .\Get-ADUserPasswordInfo.ps1 -UserName johndoe
   ```

3. **Check prerequisites**  
   Some scripts require specific modules (e.g., AzureRM, ActiveDirectory). Check the top of each script for `#Requires` statements.

---

## 🛠️ Contributing

Pull requests are welcome! If you have a useful script or improvement, feel free to submit it.

---

## 📖 License

This repository is provided as-is for educational and operational use.

---

## ✍️ Author

README written by **GitHub Copilot** 🤖  

---

> ![PowerShell Banner](https://raw.githubusercontent.com/PowerShell/PowerShell/master/assets/ps_black_128.svg)
>
> _Automate. Manage. Empower._
