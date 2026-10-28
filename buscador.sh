#!/usr/bin/env bash
set -Eeuo pipefail

readonly DEFAULT_BASE_URL="https://resultados.tse.jus.br/oficial"
readonly -a CARGOS=(6 7 5 3 1)

BASE_URL="${TSE_RESULTS_BASE_URL:-$DEFAULT_BASE_URL}"
YEAR="${TSE_RESULTS_YEAR:-2026}"
UF="${TSE_RESULTS_UF:-ma}"
MUNICIPIO="${TSE_RESULTS_MUNICIPALITY:-todos}"
TURN="${TSE_RESULTS_TURN:-1}"
LIMIT="${TSE_RESULTS_LIMIT:-20}"
FEDERAL_ELECTION="${TSE_RESULTS_FEDERAL_ELECTION:-6257}"
STATE_ELECTION="${TSE_RESULTS_STATE_ELECTION:-6259}"
FEDERAL_ELECTION_2="${TSE_RESULTS_FEDERAL_ELECTION_2:-6258}"
STATE_ELECTION_2="${TSE_RESULTS_STATE_ELECTION_2:-6260}"
COLOR_MODE="${TSE_RESULTS_COLOR:-auto}"

die() {
  printf 'Erro: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'Aviso: %s\n' "$*" >&2
}

usage() {
  cat <<'HELP'
Uso: bash buscador.sh [opções]

  --turno 1|2|ambos       Turno consultado (padrão: 1).
  --municipio todos|COD  Todos os municípios ou um código TSE de 5 dígitos.
  --limite N            Candidatos por tabela (padrão: 20; 0 mostra todos).
  --help                Mostra esta ajuda.

Exemplos:
  bash buscador.sh --turno 1
  bash buscador.sh --turno 2 --municipio 07242
  bash buscador.sh --turno ambos --municipio 07242 --limite 5

UF padrão: Maranhão.
Requer Bash 4.3 ou superior, curl e jq.
Votos são do município; a situação vem da eleição do cargo.
HELP
}

while (( $# )); do
  case "$1" in
    --turno|--municipio|--limite)
      (( $# >= 2 )) || die "falta o valor de $1"

      case "$1" in
        --turno) TURN="$2" ;;
        --municipio) MUNICIPIO="$2" ;;
        --limite) LIMIT="$2" ;;
      esac

      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "opção desconhecida: $1. Use --help"
      ;;
  esac
done

(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3) )) \
  || die "é necessário Bash 4.3 ou superior"

command -v curl >/dev/null || die "curl não encontrado; instale curl"
command -v jq >/dev/null || die "jq não encontrado; instale jq"

[[ "$UF" =~ ^[[:alpha:]]{2}$ ]] \
  || die "TSE_RESULTS_UF deve conter duas letras"

[[ "$MUNICIPIO" == todos || "$MUNICIPIO" =~ ^[0-9]{5}$ ]] \
  || die "município deve ser todos ou um código TSE de cinco dígitos"

[[ "$YEAR" =~ ^[0-9]{4}$ ]] \
  || die "TSE_RESULTS_YEAR deve conter quatro dígitos"

[[ "$TURN" =~ ^(1|2|ambos)$ ]] \
  || die "turno deve ser 1, 2 ou ambos"

[[ "$LIMIT" =~ ^(0|[1-9][0-9]*)$ ]] \
  || die "limite deve ser um inteiro não negativo"

for election_code in \
  "$FEDERAL_ELECTION" "$STATE_ELECTION" \
  "$FEDERAL_ELECTION_2" "$STATE_ELECTION_2"; do

  [[ "$election_code" =~ ^[1-9][0-9]*$ ]] \
    || die "códigos de eleição devem ser inteiros positivos sem zeros iniciais"
done

[[ "$COLOR_MODE" =~ ^(auto|always|never)$ ]] \
  || die "TSE_RESULTS_COLOR deve ser auto, always ou never"

UF="${UF,,}"
BASE_URL="${BASE_URL%/}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# Retorno: 0 = recebido; 2 = indisponível; 1 = falha.
# Não repete erros 404.
fetch_json() {
  local url="$1" destination="$2" http
  FETCH_ERROR=""

  if ! http="$(curl --silent --show-error --location \
    --retry 2 --retry-delay 1 --connect-timeout 10 --max-time 30 \
    --output "$destination" --write-out '%{http_code}' "$url" \
    2>"$tmp_dir/curl-error.txt")"; then

    FETCH_ERROR="falha de rede: $(<"$tmp_dir/curl-error.txt")"
    return 1
  fi

  case "$http" in
    200)
      ;;
    404|410)
      FETCH_ERROR="arquivo ainda não disponível (HTTP $http)"
      return 2
      ;;
    *)
      FETCH_ERROR="servidor respondeu HTTP $http"
      return 1
      ;;
  esac

  jq -e 'type == "object"' "$destination" >/dev/null 2>&1 \
    || {
      FETCH_ERROR="resposta não contém um objeto JSON válido"
      return 1
    }
}

valid_result() {
  jq -e \
    --arg election "$2" \
    --arg turn "$3" \
    --arg cargo "$4" \
    --arg scope "$5" '
      (.ele | tostring) == $election
      and (.t | tostring) == $turn
      and (.cdabr | tostring | ascii_downcase) == $scope
      and (.carg | type == "array")
      and any(.carg[]; (.cd | tostring) == $cargo)
    ' "$1" >/dev/null 2>&1
}

use_color=false

if [[ "$COLOR_MODE" == always ]] || {
  [[ "$COLOR_MODE" == auto && -t 1 && "${TERM:-dumb}" != dumb ]] \
    && [[ ! -v NO_COLOR ]]
}; then
  use_color=true
fi

print_rule() {
  local name_width="$1" number_width="$2"
  local votes_width="$3" status_width="$4"

  printf '+-%*s-+-%*s-+-%*s-+-%*s-+\n' \
    "$name_width" '' \
    "$number_width" '' \
    "$votes_width" '' \
    "$status_width" '' | tr ' ' '-'
}

print_table() {
  local -n table_rows="$1"

  local name_width=${#name_header}
  local number_width=${#number_header}
  local votes_width=${#votes_header}
  local status_width=${#status_header}
  local row name number votes status

  for row in "${table_rows[@]}"; do
    IFS=$'\t' read -r name number votes status <<<"$row"

    (( ${#name} > name_width )) && name_width=${#name}
    (( ${#number} > number_width )) && number_width=${#number}
    (( ${#votes} > votes_width )) && votes_width=${#votes}
    (( ${#status} > status_width )) && status_width=${#status}
  done

  print_rule "$name_width" "$number_width" "$votes_width" "$status_width"

  printf '| %s%*s | %*s%s | %*s%s | %s%*s |\n' \
    "$name_header" "$((name_width - ${#name_header}))" '' \
    "$((number_width - ${#number_header}))" '' "$number_header" \
    "$((votes_width - ${#votes_header}))" '' "$votes_header" \
    "$status_header" "$((status_width - ${#status_header}))" ''

  print_rule "$name_width" "$number_width" "$votes_width" "$status_width"

  for row in "${table_rows[@]}"; do
    IFS=$'\t' read -r name number votes status <<<"$row"

    if $use_color; then
      printf '| \033[36m%s%*s\033[0m | %*s%s | \033[32m%*s%s\033[0m | %s%*s |\n' \
        "$name" "$((name_width - ${#name}))" '' \
        "$((number_width - ${#number}))" '' "$number" \
        "$((votes_width - ${#votes}))" '' "$votes" \
        "$status" "$((status_width - ${#status}))" ''
    else
      printf '| %s%*s | %*s%s | %*s%s | %s%*s |\n' \
        "$name" "$((name_width - ${#name}))" '' \
        "$((number_width - ${#number}))" '' "$number" \
        "$((votes_width - ${#votes}))" '' "$votes" \
        "$status" "$((status_width - ${#status}))" ''
    fi
  done

  print_rule "$name_width" "$number_width" "$votes_width" "$status_width"
}

readonly name_header="NOME"
readonly number_header="NÚMERO"
readonly votes_header="VOTOS"
readonly status_header="SITUAÇÃO"

election_for_cargo() {
  case "$1:$2" in
    1:1)
      printf '%s' "$FEDERAL_ELECTION"
      ;;
    1:2)
      printf '%s' "$FEDERAL_ELECTION_2"
      ;;
    3:1|5:1|6:1|7:1)
      printf '%s' "$STATE_ELECTION"
      ;;
    3:2)
      printf '%s' "$STATE_ELECTION_2"
      ;;
    *)
      return 1
      ;;
  esac
}

printf 'Preparando a consulta aos dados do TSE...\n'

metadata="$tmp_dir/eleicoes.json"

fetch_json "$BASE_URL/comum/config/ele-c.json" "$metadata" \
  || die "não foi possível obter a configuração das eleições: $FETCH_ERROR"

jq -e '.pl | type == "array"' "$metadata" >/dev/null \
  || die "configuração de eleições inválida"

municipios_json="$tmp_dir/municipios.json"
municipios_file="$tmp_dir/municipios.tsv"

printf -v election_padded '%06d' "$STATE_ELECTION"

fetch_json \
  "$BASE_URL/ele$YEAR/$STATE_ELECTION/config/mun-e${election_padded}-cm.json" \
  "$municipios_json" \
  || die "não foi possível obter a lista de municípios: $FETCH_ERROR"

jq -er --arg uf "$UF" --arg municipality "$MUNICIPIO" '
  [
    .abr[]
    | select(.cd == $uf)
    | .mu[]
    | select($municipality == "todos" or .cd == $municipality)
  ] as $municipios

  | if ($municipios | length) == 0 then
      error("nenhum município encontrado")

    elif all(
      $municipios[];
      (.cd | type == "string")
      and (.cd | test("^[0-9]{5}$"))
      and (.nm | type == "string")
    ) then
      $municipios
      | unique_by(.cd)
      | sort_by(.nm)
      | .[]
      | [.cd, (.nm | gsub("[[:cntrl:]]"; " "))]
      | @tsv

    else
      error("lista de municípios inválida")
    end
' "$municipios_json" >"$municipios_file" \
  || die "lista de municípios inválida ou município não encontrado na UF $UF"

mapfile -t municipios <"$municipios_file"

turns=("$TURN")
[[ "$TURN" != ambos ]] || turns=(1 2)

jobs_file="$tmp_dir/consultas.tsv"
: >"$jobs_file"

# A configuração informa quais cargos e UFs participam de cada turno.
for turn in "${turns[@]}"; do
  for cargo in "${CARGOS[@]}"; do
    election="$(election_for_cargo "$cargo" "$turn")" || continue

    cargo_name="$(jq -r \
      --arg cycle "ele$YEAR" \
      --arg election "$election" \
      --arg turn "$turn" \
      --arg cargo "$cargo" \
      --arg uf "$UF" '
        [
          .pl[]
          | select(.c == $cycle)
          | .e[]
          | select(
              (.cd | tostring) == $election
              and (.t | tostring) == $turn
            )
          | .abr[]
          | select(.cd == "br" or .cd == $uf)
          | .cp[]
          | select((.cd | tostring) == $cargo)
          | .ds
        ]
        | first // empty
      ' "$metadata")"

    if [[ -z "$cargo_name" ]]; then
      printf 'Cargo %s: sem disputa configurada para %s no %sº turno.\n' \
        "$cargo" "${UF^^}" "$turn"
      continue
    fi

    printf '%s\t%s\t%s\t%s\n' \
      "$turn" "$cargo" "$election" "$cargo_name" >>"$jobs_file"

    printf 'Carregando situação oficial: %s, %sº turno...\n' \
      "$cargo_name" "$turn"

    # A eleição é definida no estado, ou no Brasil para presidente.
    # A colocação em um município não determina quem foi eleito.
    scope="$UF"
    [[ "$cargo" != 1 ]] || scope=br

    status_file="$tmp_dir/status-$turn-$cargo.json"
    global_file="$tmp_dir/global-$turn-$cargo.json"

    printf '{}\n' >"$status_file"
    printf -v cargo_padded '%04d' "$cargo"
    printf -v election_padded '%06d' "$election"

    url="$BASE_URL/ele$YEAR/$election/dados/$scope/${scope}-c${cargo_padded}-e${election_padded}-u.json"

    if fetch_json "$url" "$global_file"; then
      if valid_result "$global_file" "$election" "$turn" "$cargo" "$scope"; then

        jq --arg cargo "$cargo" '
          [
            .carg[]
            | select((.cd | tostring) == $cargo)
            | .. | objects | .cand? // empty | .[]
            | {
                key: (.n | tostring),
                value: {
                  e: (.e // "n"),
                  st: (.st // "")
                }
              }
          ]
          | from_entries
        ' "$global_file" >"$status_file" \
          || die "falha ao ler as situações de $cargo_name"

      else
        warn "resposta estadual/nacional inválida para $cargo_name no ${turn}º turno; situação não disponível"
      fi
    else
      warn "situação de $cargo_name no ${turn}º turno não disponível: $FETCH_ERROR"
    fi
  done
done

mapfile -t jobs <"$jobs_file"

if (( ${#jobs[@]} == 0 )); then
  printf 'Nenhum cargo disponível para a seleção informada.\n'
  exit 0
fi

success=0
unavailable=0
errors=0

printf '\nMunicípios selecionados: %s | UF: %s\n' \
  "${#municipios[@]}" "${UF^^}"

printf 'Votos: município. Situação: eleição do cargo (estado ou Brasil).\n'
printf 'ELEITO é uma indicação oficial do TSE; Não informada significa ausência dessa informação.\n'

for turn in "${turns[@]}"; do
  turn_jobs=()

  for job in "${jobs[@]}"; do
    IFS=$'\t' read -r job_turn _ <<<"$job"
    [[ "$job_turn" != "$turn" ]] || turn_jobs+=("$job")
  done

  (( ${#turn_jobs[@]} > 0 )) || continue

  printf '\n========== %sº TURNO ==========\n' "$turn"

  for municipio_row in "${municipios[@]}"; do
    IFS=$'\t' read -r municipio municipio_nome <<<"$municipio_row"

    printf '\nUF: %s | Município: %s (código TSE: %s) | %sº turno\n' \
      "${UF^^}" "$municipio_nome" "$municipio" "$turn"

    for job in "${turn_jobs[@]}"; do
      IFS=$'\t' read -r _ cargo election cargo_name <<<"$job"

      file="$tmp_dir/cargo-$cargo.json"
      printf -v cargo_padded '%04d' "$cargo"
      printf -v election_padded '%06d' "$election"

      url="$BASE_URL/ele$YEAR/$election/dados/$UF/${UF}${municipio}-c${cargo_padded}-e${election_padded}-u.json"

      printf '\n%s (cargo %s)\n' "$cargo_name" "$cargo"

      if fetch_json "$url" "$file"; then
        if ! valid_result "$file" "$election" "$turn" "$cargo" "$municipio"; then
          warn "resposta inválida para $municipio_nome, $cargo_name, ${turn}º turno"
          (( errors += 1 ))
          continue
        fi
      else
        result=$?

        if (( result == 2 )); then
          printf 'Sem dados disponíveis para este município, cargo e turno.\n'
          (( unavailable += 1 ))
        else
          warn "$municipio_nome, $cargo_name, ${turn}º turno: $FETCH_ERROR"
          (( errors += 1 ))
        fi

        continue
      fi

      rows_file="$tmp_dir/cargo-$cargo.tsv"

      if ! jq -r \
        --arg cargo "$cargo" \
        --argjson limit "$LIMIT" \
        --slurpfile status "$tmp_dir/status-$turn-$cargo.json" '

        def clean:
          tostring | gsub("[[:cntrl:]]"; " ");

        [
          .carg[]
          | select((.cd | tostring) == $cargo)
          | .. | objects | .cand? // empty | .[]
          | select((.nmu // "") != "" and (.n // "") != "")
          | . as $candidate
          | (.n | tostring) as $number
          | ($status[0][$number] // $candidate) as $s

          | {
              nome: (.nmu | clean),
              numero: $number,

              votos: (
                (.vap // "0")
                | if . == "" then 0 else tonumber end
              ),

              situacao: (
                if $s.e == "s"
                  or (($s.st // "") | test("^eleit[oa]( |$)"; "i"))
                then
                  "ELEITO"

                elif ($s.st // "") != "" then
                  ($s.st | clean)

                else
                  "Não informada"
                end
              )
            }
        ]

        | unique_by(.numero)
        | sort_by([-.votos, (.nome | ascii_downcase), .numero])
        | (if $limit == 0 then . else .[:$limit] end)[]
        | [.nome, .numero, (.votos | tostring), .situacao]
        | @tsv

      ' "$file" >"$rows_file"; then

        warn "dados de candidatos inválidos para $municipio_nome, $cargo_name"
        (( errors += 1 ))
        continue
      fi

      mapfile -t rows <"$rows_file"

      if (( ${#rows[@]} == 0 )); then
        printf 'Nenhum candidato disponível neste arquivo.\n'
        (( unavailable += 1 ))
        continue
      fi

      print_table rows
      (( success += 1 ))
    done
  done
done

printf '\nResumo: %s tabelas apresentadas; %s consultas sem dados; %s falhas.\n' \
  "$success" "$unavailable" "$errors"

(( errors == 0 )) || exit 1
