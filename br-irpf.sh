#!/bin/bash -e
# @installable
# adds a new BUY/SELL operation
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $MYDIR/log.sh
source $(real require.sh)

query=$MYDIR/psql.sh

## tips
# BENS E DIREITOS
# * formato exemplo para o campo discriminação: POSICAO LOLO3: * 2021: 100 * 2022: 110
#       no exemplo acima tinha 100 em 2021 e comprou mais 10 em 2022. se não comprou nada, só repete.
# * negociado em bolsa: sim - bota o ticker LOLO3
# * os valores de "situação" é a posição acumulada. se não tiver comprado, repete a do ano anterior, senão, soma o custo desse ano com a do ano anterior
# DIVIDENDOS
# DIVIDENDOS EXTERIOR
# * até 1900/mês isento? confirmar
# * não precisa de porra de carne leão só pra dividendo, só cadastrar o que ganhou em 
#   "rendimentos tributáveis recebidos de pf e do exterior pelo titular, tab "outras informações", coluna "exterior"
# * depois, em "imposto pago/retido", colocar os 30% do total de dividendos no item 02, imposto pago no exterior. 
#   se antes disso não aparecer nada pra pagar de imposto, o programa vai mostar um aviso de que o valor vai ser usado apenas pra referencia, porque não tem o que deduzir

fiscal_year=$(($(now.sh -y)-1))

$MYDIR/position.sh -y $fiscal_year --select tax_id,ticker.kind

info "dividends BRL..."
$MYDIR/select-dividends.sh -y $fiscal_year -c BRL --group-by-ticker --select tax_id,ticker.kind

info "dividends USD..."
$MYDIR/select-dividends.sh -y $fiscal_year -c USD --group-by-month
