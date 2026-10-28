# Consulta de Resultados Eleitorais do Maranhão

## Objetivo

Melhorar o script buscador.sh para consultar resultados do TSE,
aplicando princípios do Manifesto Ágil e práticas de XP.

## Diagnóstico inicial

O programa original consultava um município por execução,
não oferecia seleção explícita de turno e não identificava
os candidatos eleitos.

## Melhorias realizadas

- Consulta de todos os municípios do Maranhão.
- Seleção do primeiro turno, segundo turno ou ambos.
- Identificação do município, turno e cargo nos resultados.
- Coluna SITUAÇÃO com a informação oficial dos candidatos.
- Distinção entre eleitos e classificados para o segundo turno.
- Validação de parâmetros e das respostas recebidas.
- Mensagens para consultas sem dados disponíveis.

A votação apresentada é municipal. A situação eleitoral vem
do resultado estadual, ou nacional no caso de presidente.

## Pré-requisitos

- Bash 4.3 ou superior.
- curl e jq.
- Conexão com a internet.

No Ubuntu, as dependências podem ser instaladas com:
`sudo apt install curl jq`

## Como executar

No Terminal, dentro da pasta do projeto:

- Todos os municípios, primeiro turno:
  `bash buscador.sh --turno 1 --municipio todos`

- Todos os municípios, segundo turno:
  `bash buscador.sh --turno 2 --municipio todos`

- Um município, nos dois turnos:
  `bash buscador.sh --turno ambos --municipio 07242 --limite 5`

O limite padrão é de 20 candidatos por tabela.
Use `--limite 0` para mostrar todos os candidatos disponíveis.
Cargos sem disputa no turno selecionado não são consultados.

## Validação

Testes realizados no Ubuntu:

- `bash -n buscador.sh`: nenhuma falha de sintaxe.
- Consulta de Davinópolis, código 07242, nos dois turnos:
  seis tabelas apresentadas e nenhuma falha.
- Conferência da distinção entre ELEITO e 2º turno.
- `--turno 3`: rejeitado com mensagem explicativa.
- `--municipio 123`: rejeitado com mensagem explicativa.
- `--limite -1`: rejeitado com mensagem explicativa.
  
O teste completo percorreu os 217 municípios nos dois turnos.
Foram apresentadas 1.301 tabelas, nenhuma consulta sem dados
e uma falha de rede por tempo de resposta esgotado.

A falha ocorreu em Presidente Sarney (08141), na consulta
de Deputado Federal do primeiro turno.

O município foi consultado novamente: cinco tabelas apresentadas,
nenhuma consulta sem dados e nenhuma falha. A consulta que
havia falhado foi validada no reteste.

Evidências: validacao_completa.txt e reteste_presidente_sarney.txt.

## Pair Programming

Daniela atuou como Driver, realizando as alterações no código.
Lavynya atuou como Navigator, acompanhando a implementação
e revisando as alterações realizadas.

## Organização no GitHub

O desenvolvimento foi realizado no fork, na branch melhoria-xp,
com commits para registrar as alterações e correções.
Após a validação, as mudanças serão integradas à main.
O desenvolvimento foi realizado no fork, na branch melhoria-xp,
com commits para registrar as alterações e correções.
Após a validação, as mudanças serão integradas à main.
