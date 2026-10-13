#!/usr/bin/env bash
set -euo pipefail

# Unattended deployment script: no prompts, no input, no Telegram.
# Override any setting by exporting it before running, e.g.
#   REGION=asia-southeast1 SERVICE=jerico-proxy ./cloud-run.sh

# ===== Logging & error handler =====
LOG_FILE="/tmp/jerico_deploy_$(date +%s).log"
touch "$LOG_FILE"
on_err() {
  local rc=$?
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
  clear
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

show_success() {
  printf "${C_404_GREEN}✓${RESET} %s\n" "$1"
}

show_info() {
  printf "${C_404_BLUE}ℹ${RESET} %s\n" "$1"
}

show_warning() {
  printf "${C_404_YELLOW}⚠${RESET} %s\n" "$1"
}

show_error() {
  printf "${C_404_RED}✗${RESET} %s\n" "$1"
}

show_divider() {
  printf "${C_404_GRAY}  ────────────────────────────────────────────────────────${RESET}\n"
}

show_kv() {
  printf "   ${C_404_GRAY}%-16s${RESET} ${C_404_CYAN}%s${RESET}\n" "$1" "$2"
}

# =================== Progress Spinner ===================
run_with_progress() {
  local label="$1"; shift
  ( "$@" ) >>"$LOG_FILE" 2>&1 &
  local pid=$!
  local pct=5
  
  if [[ -t 1 ]]; then
    printf "\e[?25l"
    while kill -0 "$pid" 2>/dev/null; do
      local step=$(( (RANDOM % 9) + 2 ))
      pct=$(( pct + step ))
      (( pct > 95 )) && pct=95
      printf "\r${C_404_PURPLE}⟳${RESET} ${C_404_CYAN}%s...${RESET} [${C_404_YELLOW}%s%%${RESET}]" "$label" "$pct"
      sleep "$(awk -v r=$RANDOM 'BEGIN{s=0.08+(r%7)/100; printf "%.2f", s }')"
    done
    wait "$pid"; local rc=$?
    printf "\r"
    if (( rc==0 )); then
      printf "${C_404_GREEN}✓${RESET} ${C_404_GREEN}%s...${RESET} [${C_404_GREEN}100%%${RESET}]\n" "$label"
    else
      printf "${C_404_RED}✗${RESET} ${C_404_RED}%s failed (see %s)${RESET}\n" "$label" "$LOG_FILE"
      return $rc
    fi
    printf "\e[?25h"
  else
    wait "$pid"
  fi
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

# =================== Step 2: Configuration ===================
# Everything below is fixed for an unattended deploy. Override any value by
# exporting it before running, e.g. REGION=asia-southeast1 ./cloud-run.sh
show_step "02" "Deployment Configuration"

REGION="${REGION:-us-central1}"
IMAGE="${IMAGE:-docker.io/jericoo/jerico}"
SERVICE="${SERVICE:-jerico-haha}"
CPU="${CPU:-8}"
MEMORY="${MEMORY:-8Gi}"
CONCURRENCY="${CONCURRENCY:-1000}"
TIMEOUT="${TIMEOUT:-3600}"
PORT="${PORT:-8080}"
PROTO="vless-ws"

show_success "Protocol: ${C_404_CYAN}VLESS WebSocket${RESET}"
show_kv "Region:" "$REGION"
show_kv "Service Name:" "$SERVICE"
show_kv "Docker Image:" "${C_404_GRAY}${IMAGE}${RESET}"
show_kv "Resources:" "${CPU} vCPU / ${MEMORY}"
show_kv "Concurrency:" "$CONCURRENCY"
show_kv "Timeout:" "${TIMEOUT}s"
show_kv "Port:" "$PORT"
show_kv "Authentication:" "Public (unauthenticated)"
show_kv "Scaling:" "min 0 / max 1"
echo "[Docker Image] ${IMAGE}" >>"$LOG_FILE"

# =================== Step 3: Enable APIs ===================
show_step "03" "GCP API Enablement"

run_with_progress "Enabling Cloud Run & Cloud Build APIs" \
  gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet

show_success "All required APIs enabled"

# =================== Step 4: Deploy ===================
show_step "04" "Cloud Run Deployment"

show_info "Deploying ${SERVICE} to ${REGION}"
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
    --concurrency=1000 \
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
show_info "Generating QR code for quick configuration..."
echo "[QR Code URL: $URI]" >> "$LOG_FILE"

# =================== Final Output ===================
printf "\n"
show_success "Deployment complete"
show_divider

printf "\n"
show_kv "Service:" "$SERVICE"
show_kv "Region:" "$REGION"
show_kv "URL:" "${URL_CANONICAL}"
show_kv "Scaling:" "min 0 / max 1  ·  concurrency ${CONCURRENCY}"
show_kv "Log file:" "$LOG_FILE"

printf "\n"
printf "  ${C_404_CYAN}${BOLD}◆${RESET} ${C_404_GRAY}JericoScript · ${SERVICE} · ${REGION} · $(date '+%Y-%m-%d %H:%M')${RESET}\n\n"
