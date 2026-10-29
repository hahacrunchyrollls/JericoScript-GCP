#!/usr/bin/env bash
set -euo pipefail

# Deployment script with interactive region selection.
# Skip the menu / override any setting by exporting it before running, e.g.
#   REGION=asia-southeast1 SERVICE=jerico-proxy ./cloud-run.sh

# ===== Logging & error handler =====
LOG_FILE="/tmp/jerico_deploy_$(date +%s).log"
touch "$LOG_FILE"
on_err() {
  local rc=$?
  printf "\e[?25h" 2>/dev/null || true
  echo "" | tee -a "$LOG_FILE"
  echo "❌ ERROR: Command failed (exit $rc) at line $LINENO: ${BASH_COMMAND}" | tee -a "$LOG_FILE" >&2
  echo "—— LOG (last 80 lines) ——" >&2
  tail -n 80 "$LOG_FILE" >&2 || true
  echo "📄 Log File: $LOG_FILE" >&2
  exit $rc
}
trap on_err ERR

# =================== Theme ===================
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\e[0m'; BOLD=$'\e[1m'; DIM=$'\e[2m'
  C_404_RED=$'\e[38;5;196m'      # Bright Red
  C_404_BLUE=$'\e[38;5;39m'      # Bright Blue
  C_404_GREEN=$'\e[38;5;46m'     # Bright Green
  C_404_YELLOW=$'\e[38;5;226m'   # Bright Yellow
  C_404_PURPLE=$'\e[38;5;93m'    # Purple
  C_404_GRAY=$'\e[38;5;244m'     # Gray
  C_404_CYAN=$'\e[38;5;51m'      # Cyan
else
  RESET= BOLD= DIM= C_404_RED= C_404_BLUE= C_404_GREEN= C_404_YELLOW= C_404_PURPLE= C_404_GRAY= C_404_CYAN=
fi

# =================== Banner ===================
show_banner() {
  [[ -t 1 ]] && clear
  printf "\n"
  printf "  ${C_404_CYAN}${BOLD}◆${RESET} ${BOLD}JericoScript${RESET} ${C_404_GRAY}·${RESET} ${C_404_CYAN}Cloud Run Deploy${RESET}\n"
  printf "  ${C_404_GRAY}VLESS WebSocket  ·  ${IMAGE:-docker.io/jericoo/jerico}${RESET}\n"
  printf "\n"
  printf "  ${C_404_GRAY}────────────────────────────────────────────────────────${RESET}\n"
  printf "\n"
}

# =================== Custom UI Functions ===================
show_step() {
  local step_num="$1"
  local step_title="$2"
  printf "\n${C_404_CYAN}${BOLD}[%s]${RESET} ${BOLD}%s${RESET}\n" "$step_num" "$step_title"
}

show_success() { printf "${C_404_GREEN}✓${RESET} %s\n" "$1"; }
show_info()    { printf "${C_404_BLUE}ℹ${RESET} %s\n" "$1"; }
show_warning() { printf "${C_404_YELLOW}⚠${RESET} %s\n" "$1" >&2; }
show_error()   { printf "${C_404_RED}✗${RESET} %s\n" "$1"; }
show_divider() { printf "${C_404_GRAY}  ────────────────────────────────────────────────────────${RESET}\n"; }
show_kv()      { printf "   ${C_404_GRAY}%-16s${RESET} ${C_404_CYAN}%s${RESET}\n" "$1" "$2"; }

# =================== Progress Spinner ===================
run_with_progress() {
  local label="$1"; shift
  ( "$@" ) >>"$LOG_FILE" 2>&1 &
  local pid=$!
  local pct=5
  local rc=0

  if [[ -t 1 ]]; then
    printf "\e[?25l"
    while kill -0 "$pid" 2>/dev/null; do
      local step=$(( (RANDOM % 9) + 2 ))
      pct=$(( pct + step ))
      (( pct > 95 )) && pct=95
      printf "\r${C_404_PURPLE}⟳${RESET} ${C_404_CYAN}%s...${RESET} [${C_404_YELLOW}%s%%${RESET}]" "$label" "$pct"
      sleep "$(awk -v r=$RANDOM 'BEGIN{s=0.08+(r%7)/100; printf "%.2f", s }')"
    done
    wait "$pid" || rc=$?
    printf "\r\e[K"
    printf "\e[?25h"
    if (( rc==0 )); then
      printf "${C_404_GREEN}✓${RESET} ${C_404_GREEN}%s...${RESET} [${C_404_GREEN}100%%${RESET}]\n" "$label"
    else
      printf "${C_404_RED}✗${RESET} ${C_404_RED}%s failed (see %s)${RESET}\n" "$label" "$LOG_FILE"
      return $rc
    fi
  else
    wait "$pid"
  fi
}

# =================== Region helpers ===================
region_name() {
  case "$1" in
    africa-south1)            echo "Johannesburg, South Africa" ;;
    asia-east1)               echo "Taiwan" ;;
    asia-east2)               echo "Hong Kong" ;;
    asia-northeast1)          echo "Tokyo, Japan" ;;
    asia-northeast2)          echo "Osaka, Japan" ;;
    asia-northeast3)          echo "Seoul, South Korea" ;;
    asia-south1)              echo "Mumbai, India" ;;
    asia-south2)              echo "Delhi, India" ;;
    asia-southeast1)          echo "Singapore" ;;
    asia-southeast2)          echo "Jakarta, Indonesia" ;;
    australia-southeast1)     echo "Sydney, Australia" ;;
    australia-southeast2)     echo "Melbourne, Australia" ;;
    europe-central2)          echo "Warsaw, Poland" ;;
    europe-north1)            echo "Finland" ;;
    europe-southwest1)        echo "Madrid, Spain" ;;
    europe-west1)             echo "Belgium" ;;
    europe-west2)             echo "London, UK" ;;
    europe-west3)             echo "Frankfurt, Germany" ;;
    europe-west4)             echo "Netherlands" ;;
    europe-west6)             echo "Zurich, Switzerland" ;;
    europe-west8)             echo "Milan, Italy" ;;
    europe-west9)             echo "Paris, France" ;;
    europe-west10)            echo "Berlin, Germany" ;;
    europe-west12)            echo "Turin, Italy" ;;
    me-central1)              echo "Doha, Qatar" ;;
    me-central2)              echo "Dammam, Saudi Arabia" ;;
    me-west1)                 echo "Tel Aviv, Israel" ;;
    northamerica-northeast1)  echo "Montréal, Canada" ;;
    northamerica-northeast2)  echo "Toronto, Canada" ;;
    northamerica-south1)      echo "Querétaro, Mexico" ;;
    southamerica-east1)       echo "São Paulo, Brazil" ;;
    southamerica-west1)       echo "Santiago, Chile" ;;
    us-central1)              echo "Iowa, USA" ;;
    us-east1)                 echo "South Carolina, USA" ;;
    us-east4)                 echo "N. Virginia, USA" ;;
    us-east5)                 echo "Columbus, USA" ;;
    us-south1)                echo "Dallas, USA" ;;
    us-west1)                 echo "Oregon, USA" ;;
    us-west2)                 echo "Los Angeles, USA" ;;
    us-west3)                 echo "Salt Lake City, USA" ;;
    us-west4)                 echo "Las Vegas, USA" ;;
    *)                        echo "-" ;;
  esac
}

select_region() {
  local -a regions=()
  local r

  # Ask Cloud Run for the regions that are actually available
  while IFS= read -r r; do
    [[ -n "$r" ]] && regions+=("$r")
  done < <(gcloud run regions list --quiet 2>>"$LOG_FILE" \
            | grep -oE '^[a-z]+-[a-z]+[0-9]+' | sort -u || true)

  # Fallback if the gcloud command is unavailable or returned nothing
  if (( ${#regions[@]} == 0 )); then
    show_warning "Could not fetch region list from gcloud, using built-in list"
    regions=(
      africa-south1 asia-east1 asia-east2 asia-northeast1 asia-northeast2
      asia-northeast3 asia-south1 asia-south2 asia-southeast1 asia-southeast2
      australia-southeast1 australia-southeast2 europe-central2 europe-north1
      europe-southwest1 europe-west1 europe-west2 europe-west3 europe-west4
      europe-west6 europe-west8 europe-west9 europe-west10 europe-west12
      me-central1 me-central2 me-west1 northamerica-northeast1
      northamerica-northeast2 northamerica-south1 southamerica-east1
      southamerica-west1 us-central1 us-east1 us-east4 us-east5 us-south1
      us-west1 us-west2 us-west3 us-west4
    )
  fi

  # Keep only regions allowed by the project's org policy (gcp.resourceLocations)
  local policy_json policy_tokens
  policy_json="$(gcloud org-policies describe gcp.resourceLocations \
                   --project="$PROJECT" --effective --format=json 2>>"$LOG_FILE" || true)"
  if grep -q 'allowedValues' <<<"$policy_json"; then
    policy_tokens="$(grep -oE 'in:[a-z0-9-]+|[a-z]+-[a-z]+[0-9]+' <<<"$policy_json" | sort -u || true)"
    local -a allowed=()
    for r in "${regions[@]}"; do
      if grep -qxE "${r}|in:${r}-locations|in:${r%%-*}-locations" <<<"$policy_tokens"; then
        allowed+=("$r")
      fi
    done
    if (( ${#allowed[@]} > 0 )); then
      regions=("${allowed[@]}")
      printf "${C_404_BLUE}ℹ${RESET} Showing only regions allowed by your project's org policy\n" >&2
    else
      show_warning "Org policy restricts locations but none matched; showing all regions"
    fi
  fi

  printf "\n${C_404_GREEN}${BOLD}🌍 AVAILABLE CLOUD RUN REGIONS:${RESET}\n\n" >&2
  local i=1
  for r in "${regions[@]}"; do
    printf "   ${C_404_YELLOW}%2d)${RESET} ${C_404_CYAN}%-26s${RESET} ${C_404_GRAY}%s${RESET}\n" \
      "$i" "$r" "$(region_name "$r")" >&2
    i=$((i+1))
  done
  printf "\n" >&2

  # Non-interactive (no terminal): use default
  if [[ ! -t 0 ]]; then
    echo "us-central1"; return
  fi

  local choice
  while true; do
    read -r -p "   Select region [number or name, Enter = us-central1]: " choice
    choice="${choice:-us-central1}"
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#regions[@]} )); then
      echo "${regions[$((choice-1))]}"; return
    fi
    for r in "${regions[@]}"; do
      if [[ "$choice" == "$r" ]]; then echo "$r"; return; fi
    done
    printf "   ${C_404_RED}✗ Invalid choice, try again.${RESET}\n" >&2
  done
}

# Show banner
show_banner

# =================== Step 1: Project ===================
show_step "01" "GCP Project Configuration"

PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT" || "$PROJECT" == "(unset)" ]]; then
  show_error "No active GCP project found."
  show_info "Please run: ${C_404_CYAN}gcloud config set project <YOUR_PROJECT_ID>${RESET}"
  exit 1
fi

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" || true
show_success "Project loaded successfully"
show_kv "Project ID:" "$PROJECT"
show_kv "Project Number:" "$PROJECT_NUMBER"

# =================== Step 2: Enable APIs ===================
# Done before the region menu: listing regions needs the Cloud Run API enabled.
show_step "02" "GCP API Enablement"

run_with_progress "Enabling Cloud Run & Cloud Build APIs" \
  gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet

# Optional: lets the region menu read the org policy (failure is not fatal)
gcloud services enable orgpolicy.googleapis.com --quiet >>"$LOG_FILE" 2>&1 || true

show_success "All required APIs enabled"

# =================== Step 3: Configuration ===================
# Region is chosen from a menu unless REGION is already exported.
show_step "03" "Deployment Configuration"

if [[ -z "${REGION:-}" ]]; then
  REGION="$(select_region)"
fi
REGION_NAME="$(region_name "$REGION")"

IMAGE="${IMAGE:-docker.io/jericoo/jerico}"
SERVICE="${SERVICE:-jerico-haha}"
CPU="${CPU:-8}"
MEMORY="${MEMORY:-8Gi}"
CONCURRENCY="${CONCURRENCY:-1000}"
TIMEOUT="${TIMEOUT:-3600}"
PORT="${PORT:-8080}"
PROTO="vless-ws"

printf "\n"
show_success "Protocol: ${C_404_CYAN}VLESS WebSocket${RESET}"
show_kv "Region:" "${REGION} (${REGION_NAME})"
show_kv "Service Name:" "$SERVICE"
show_kv "Docker Image:" "${C_404_GRAY}${IMAGE}${RESET}"
show_kv "Resources:" "${CPU} vCPU / ${MEMORY}"
show_kv "Concurrency:" "$CONCURRENCY"
show_kv "Timeout:" "${TIMEOUT}s"
show_kv "Port:" "$PORT"
show_kv "Authentication:" "Public (unauthenticated)"
show_kv "Scaling:" "min 0 / max 1"
echo "[Docker Image] ${IMAGE}" >>"$LOG_FILE"
echo "[Region] ${REGION} (${REGION_NAME})" >>"$LOG_FILE"

# =================== Step 4: Deploy ===================
show_step "04" "Cloud Run Deployment"

show_info "Deploying ${SERVICE} to ${REGION} (${REGION_NAME})"
show_kv "Image:" "${C_404_GRAY}${IMAGE}${RESET}"
show_kv "Resources:" "${CPU} vCPU / ${MEMORY} / ${CONCURRENCY} req"
printf "\n"

run_with_progress "Deploying ${SERVICE} to Cloud Run" \
  gcloud run deploy "$SERVICE" \
    --image="$IMAGE" \
    --platform=managed \
    --region="$REGION" \
    --memory="$MEMORY" \
    --cpu="$CPU" \
    --concurrency="$CONCURRENCY" \
    --timeout="$TIMEOUT" \
    --allow-unauthenticated \
    --port="$PORT" \
    --min-instances=0 \
    --max-instances=1 \
    --cpu-boost \
    --quiet

# =================== Step 5: Result ===================
show_step "05" "Deployment Result"

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" || true
CANONICAL_HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
URL_CANONICAL="https://${CANONICAL_HOST}"

printf "\n"
show_success "VLESS WS Service is live"
show_divider

printf "\n${C_404_GREEN}${BOLD}📡 SERVICE ENDPOINT:${RESET}\n"
printf "   ${C_404_CYAN}${BOLD}%s${RESET}\n\n" "${URL_CANONICAL}"

# =================== VLESS Configuration ===================
# These credentials and paths are what the bundled v2ray in ${IMAGE} serves
# (main.go / config.json in the image source). The client also has to present the
# service hostname as the WS Host header, which is what Cloud Run routes on.
VLESS_UUID="8f6dc3de-826a-4a1f-9ab2-70b225a8f9d2"
TROJAN_PASSWORD="jerico"
SS_PASSWORD="jerico"
SS_METHOD="aes-256-gcm"
PATH_VLESS="/vless"
PATH_VMESS="/vmess"
PATH_TROJAN="/trojan"
PATH_SS="/shadowsocks"

URI="vless://${VLESS_UUID}@vpn.googleapis.com:443?path=%2Fvless&security=tls&encryption=none&host=${CANONICAL_HOST}&type=ws&sni=${CANONICAL_HOST}#JericoScript-VLESS"

printf "${C_404_GREEN}${BOLD}🔑 VLESS CONFIGURATION:${RESET}\n"
printf "   ${C_404_CYAN}%s${RESET}\n\n" "${URI}"

printf "${C_404_GREEN}${BOLD}📋 CONFIGURATION DETAILS:${RESET}\n"
show_kv "UUID:" "$VLESS_UUID"
show_kv "Address:" "vpn.googleapis.com"
show_kv "Port:" "443"
show_kv "Path:" "$PATH_VLESS"
show_kv "Security:" "TLS"
show_kv "Transport:" "WebSocket"
show_kv "Host / SNI:" "${CANONICAL_HOST}"
show_divider

# =================== QR Code Display ===================
printf "\n${C_404_GREEN}${BOLD}📱 QR CODE (Scan with V2Ray client):${RESET}\n"
if command -v qrencode >/dev/null 2>&1; then
  qrencode -t ANSIUTF8 "$URI" || true
else
  show_info "Install 'qrencode' to display a QR code here (e.g. apt install qrencode)"
fi
echo "[QR Code URL: $URI]" >> "$LOG_FILE"

# =================== Final Output ===================
printf "\n"
show_success "Deployment complete"
show_divider

printf "\n"
show_kv "Service:" "$SERVICE"
show_kv "Region:" "${REGION} (${REGION_NAME})"
show_kv "URL:" "${URL_CANONICAL}"
show_kv "Scaling:" "min 0 / max 1  ·  concurrency ${CONCURRENCY}"
show_kv "Log file:" "$LOG_FILE"

printf "\n"
printf "  ${C_404_CYAN}${BOLD}◆${RESET} ${C_404_GRAY}JericoScript · ${SERVICE} · ${REGION} · $(date '+%Y-%m-%d %H:%M')${RESET}\n\n"
