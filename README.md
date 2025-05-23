# SubEnum - Automated Subdomain Enumeration Script

This Bash script automates the process of subdomain enumeration and reconnaissance for a given domain. It integrates several popular tools to gather subdomains, check their status, take screenshots, and generate a summary report.

---

## Features

- Checks required dependencies (`subfinder`, `assetfinder`, `amass`, `gau`, `httpx`, `ffuf`, `gowitness`, `eyewitness`, `katana`, `curl`, `jq`).
- Runs subdomain enumeration tools: Subfinder, Assetfinder, Amass, crt.sh scraping.
- Performs subdomain and virtual host fuzzing using `ffuf`.
- Aggregates and cleans subdomain results.
- Checks which subdomains are live using `httpx`.
- Takes screenshots of live subdomains with `gowitness` and `EyeWitness`.
- Crawls live URLs with `katana`.
- Generates a report summarizing the results.

---

## Usage

```bash
./subenum.sh -d <domain> [-o <output_directory>]
```

## Dependencies
Make sure the following tools are installed and available in your $PATH:

- subfinder
- assetfinder
- amass
- httpx
- ffuf
- aquatone
- gowitness
- eyewitness
- gau
- katana
- hakrawler
- curl
- jq
