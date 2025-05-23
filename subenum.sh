#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_dependencies() {
    echo -e "${YELLOW}[+] Checking dependencies...${NC}"
    for cmd in subfinder assetfinder amass gau httpx ffuf aquatone gowitness eyewitness katana curl; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}[-] $cmd is not installed.${NC}"
            exit 1
        fi
    done
}

ask_run() {
    read -p "Do you want to run $1? (y/n): " response
    [[ "$response" =~ ^[Yy]$ ]]
}

usage() {
    echo -e "${GREEN}Usage: $0 -d <domain>${NC}"
    exit 1
}

while getopts "d:o:" opt; do
    case $opt in
        d) DOMAIN=$OPTARG ;;
        o) OUTPUT_DIR=$OPTARG ;;
        *) usage ;;
    esac
done

if [ -z "$DOMAIN" ]; then
    usage
fi

# If -o is provided, expand ~ to $HOME, then append domain
if [ -n "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="${OUTPUT_DIR/#\~/$HOME}"
    OUTPUT_DIR="${OUTPUT_DIR%/}/$DOMAIN"  # ensure no trailing slash before appending domain
else
    # If -o not provided, just use domain as output dir (current dir/domain)
    OUTPUT_DIR="$DOMAIN"
fi

mkdir -p "$OUTPUT_DIR"
echo -e "${GREEN}[+] Output will be saved in $OUTPUT_DIR${NC}"

check_dependencies

# Subdomain enumeration
echo -e "${YELLOW}[*] Running Subfinder...${NC}"
subfinder -d "$DOMAIN" -silent > "$OUTPUT_DIR/subfinder.txt"
echo -e "${GREEN}[+] Subfinder done.${NC}"

echo -e "${YELLOW}[*] Running Assetfinder...${NC}"
assetfinder --subs-only "$DOMAIN" > "$OUTPUT_DIR/assetfinder.txt"
echo -e "${GREEN}[+] Assetfinder done.${NC}"

echo -e "${YELLOW}[*] Running Amass...${NC}"
amass enum -passive -d "$DOMAIN" > "$OUTPUT_DIR/amass.txt"
echo -e "${GREEN}[+] Amass done.${NC}"

echo -e "${YELLOW}[*] Scraping crt.sh...${NC}"
curl -s "https://crt.sh/?q=%25.$DOMAIN" |
  grep -oP "(?<=<TD>)[a-zA-Z0-9\\.*\\-]+(?=</TD>)" |
  grep "$DOMAIN" |
  sed 's/\\*\\.//g' |
  sort -u > "$OUTPUT_DIR/crtsh.txt"
echo -e "${GREEN}[+] crt.sh scraping done.${NC}"

if ask_run "ffuf subdomain bruteforce"; then
    read -p "Enter path to wordlist [default: /usr/share/wordlists/dirb/common.txt]: " WORDLIST
    WORDLIST=${WORDLIST:-/usr/share/wordlists/dirb/common.txt}
    
    read -p "Enter number of threads [default: 3]: " THREADS
    THREADS=${THREADS:-3}
    
    read -p "Enter delay between requests in seconds [default: 1]: " DELAY
    DELAY=${DELAY:-1}

    mkdir -p "$OUTPUT_DIR/ffuf"

    echo -e "${YELLOW}[*] Running ffuf vhost fuzzing against $DOMAIN using $WORDLIST${NC}"
    ffuf -u "https://$DOMAIN" -H "Host: FUZZ.$DOMAIN" \
        -w "$WORDLIST" \
        -t "$THREADS" -p "$DELAY" \
        -fc 403,404 \
        -of json -o "$OUTPUT_DIR/ffuf/ffuf_vhost.json"

    echo -e "${YELLOW}[*] Running ffuf subdomain fuzzing against $DOMAIN using $WORDLIST${NC}"
    ffuf -u "https://FUZZ.$DOMAIN" \
        -w "$WORDLIST" \
        -t "$THREADS" -p "$DELAY" \
        -fc 403,404 \
        -of json -o "$OUTPUT_DIR/ffuf/ffuf_subdomain.json"

    echo -e "${GREEN}[+] ffuf vhost and subdomain fuzzing done.${NC}"

    echo -e "${YELLOW}[*] Extracting subdomains from ffuf JSON results...${NC}"
    jq -r '
    	.results[] |
    	(
        	if .url then
            		(.url | sub("https?://";"") | split("/")[0])
        	elif .host then
            		.host
        	else empty
        	end
    	)
' "$OUTPUT_DIR/ffuf/ffuf_vhost.json" "$OUTPUT_DIR/ffuf/ffuf_subdomain.json" |
    sed 's/^www\.//' | grep -v '\*' | sort -fu > "$OUTPUT_DIR/ffuf/ffuf_subs.txt"

    echo -e "${GREEN}[+] Extracted unique subdomains saved to $OUTPUT_DIR/ffuf/ffuf_subs.txt${NC}"
fi

cat "$OUTPUT_DIR"/subfinder.txt \
    "$OUTPUT_DIR"/assetfinder.txt \
    "$OUTPUT_DIR"/crtsh.txt \
    "$OUTPUT_DIR"/ffuf/ffuf_subs.txt 2>/dev/null |
    sed 's/^www\.//' |
    grep -v '\*' |
    sort -fu > "$OUTPUT_DIR/all_subs.txt"

echo -e "${GREEN}[+] Total unique cleaned subdomains: $(wc -l < "$OUTPUT_DIR/all_subs.txt")${NC}"

# Live check
echo -e "${YELLOW}[*] Checking which subdomains are live with httpx...${NC}"
httpx -l "$OUTPUT_DIR/all_subs.txt" -silent > "$OUTPUT_DIR/live.txt"
echo -e "${GREEN}[+] Live subdomains: $(wc -l < "$OUTPUT_DIR/live.txt")${NC}"

# aquatone
if ask_run "aquatone screeshots"; then
    echo -e "${YELLOW}[*] Running aquatone...${NC}"
    mkdir -p "$OUTPUT_DIR/aquatone"
    cat "$OUTPUT_DIR/live.txt" | aquatone -ports large -http-timeout 10000 -screenshot-timeout 10000 -threads 1 -out "$OUTPUT_DIR/aquatone"
    echo -e "${GREEN}[+] aquatone done.${NC}"
fi

# gowitness
if ask_run "gowitness screenshots"; then
    echo -e "${YELLOW}[*] Running gowitness...${NC}"
    mkdir -p "$OUTPUT_DIR/gowitness"
    gowitness scan file -f "$OUTPUT_DIR/live.txt" -s "$OUTPUT_DIR/gowitness"
    echo -e "${GREEN}[+] gowitness done.${NC}"
fi

# eyewitness
if ask_run "EyeWitness screenshots"; then
    echo -e "${YELLOW}[*] Running EyeWitness...${NC}"
    mkdir -p "$OUTPUT_DIR/eyewitness"
    eyewitness --web -f "$OUTPUT_DIR/live.txt" --no-prompt -d "$OUTPUT_DIR/eyewitness"
    echo -e "${GREEN}[+] EyeWitness done.${NC}"
fi

# gau
echo -e "${YELLOW}[*] Running gau...${NC}"
gau "$DOMAIN" > "$OUTPUT_DIR/gau.txt"
echo -e "${GREEN}[+] gau done.${NC}"

# katana
echo -e "${YELLOW}[*] Running katana...${NC}"
katana -list "$OUTPUT_DIR/live.txt" -o "$OUTPUT_DIR/katana.txt"
echo -e "${GREEN}[+] katana done.${NC}"

# hakrawler
echo -e "${YELLOW}[*] Running hakrawler...${NC}"
cat "$OUTPUT_DIR/live.txt" | hakrawler -u > "$OUTPUT_DIR/hakrawler.txt"
echo -e "${GREEN}[+] hakrawler done.${NC}"

# Report
REPORT_FILE="$OUTPUT_DIR/report.txt"
echo -e "${YELLOW}[*] Generating report...${NC}"
{
    echo "Report for $DOMAIN"
    echo "===================="
    echo
    echo "Clean Subdomains: $(wc -l < "$OUTPUT_DIR/all_subs.txt")"
    echo "Live Subdomains: $(wc -l < "$OUTPUT_DIR/live.txt")"
    [ -f "$OUTPUT_DIR/gau.txt" ] && echo "GAU URLs: $(wc -l < "$OUTPUT_DIR/gau.txt")"
    [ -f "$OUTPUT_DIR/katana.txt" ] && echo "Katana URLs: $(wc -l < "$OUTPUT_DIR/katana.txt")"
} > "$REPORT_FILE"
echo -e "${GREEN}[+] Report saved at $REPORT_FILE${NC}"
