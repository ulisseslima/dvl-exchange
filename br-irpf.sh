#!/bin/bash -e
# @installable
# dados do ano anterior para fins de IR. primeiro arg pode ser o ano desejado.
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
#   se antes disso não aparecer nada pra pagar de imposto, o programa vai mostrar um aviso de que o valor vai ser usado apenas pra referencia,
#   porque não tem o que deduzir
# * se um dia o haddad decidir que não tem mais acordo de não-bi-tributação, vai ter que pagar. Até lá, está ok

default=$(now.sh -y)
this_year=${1:-$default}
fiscal_year=$((${this_year}-1))

# a ideia do campo discriminação do IR é ter a quantidade atual daquela ação.
# mas eu coloco a quantidade do ano anterior também, pra ter controle maior.
# o actual amount não importa aqui porque o que conta é o que comprou naquele ano
# o que não aparecer aqui só troca o ano e mantém o valor do ano anterior
# o que aparecer, soma o total anterior com o total comprado no ano.
# Quando tiver desdobramento/agrupamento, em vez de somar o comprado no ano com o amount do ano anterior, apenas colocar o total atual.
echo "########### BENS E DIREITOS - COMPRADOS EM ${fiscal_year} #####################"
$MYDIR/position.sh -y $fiscal_year --select "coalesce(tax_id,ticker.institution) as tax_id,ticker.kind"
echo "///" && echo

echo "########### BENS E DIREITOS - RENDA FIXA #####################"
$MYDIR/select-fixed-income.sh --until ${this_year}-01-01 --totals
echo "///" && echo

# também incluir aqui o relatório do contador
echo "########### Rendimentos Isentos e Não Tributáveis ################"
$MYDIR/select-dividends.sh -y $fiscal_year -c BRL --group-by-ticker --select "coalesce(tax_id,ticker.institution) as tax_id,ticker.kind" --no-plot
echo "///" && echo

# envolve duas abas:
# 1. Rendimentos tributáveis recebidos de PF e do exterior pelo titular
# aqui preencher apenas na aba "outras informações" com o total de dividendos recebidos na coluna "Exterior".
# o valor é o total de dividendos recebidos em brl, que é o valor total em brl, já convertido.
# 2. Imposto pago/retido
# aqui preencher o 02. imposto pago no exterior, que é 30% do total de dividendos recebidos
# taxes_in_brl são os 30% de imposto cobrados nos eua, usar esse valor.
# conferir se o brl do aggregated sum bate com o que foi colocado no IR.
# no final, ele mostra um aviso dizendo que o valor foi usado apenas pra referência, porque não tem imposto a pagar.
echo "########### Rend Trib Recebidos de PF/Exterior + Imposto Pago/Retido ################"
$MYDIR/select-dividends.sh -y $fiscal_year -c USD --group-by-month
echo "///" && echo

# depois de enviar a declaração, imprimir o recibo e o pdf.
