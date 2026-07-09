# Comando: /ui-ux-pro-max

## Uso
`/ui-ux-pro-max [query] [opções]`

## Descrição
Busca recomendações de design do ui-ux-pro-max-skill para aplicar no DiPertin.

## Sintaxe
```bash
# Busca básica
python3 ui-ux-pro-max-skill/src/ui-ux-pro-max/scripts/search.py "QUERY"

/# Busca por domínio específico
python3 ui-ux-pro-max-skill/src/ui-ux-pro-max/scripts/search.py "QUERY" --domain <domínio>

# Busca por stack de tecnologia
python3 ui-ux-pro-max-skill/src/ui-ux-pro-max/scripts/search.py "QUERY" --stack <stack>

# Limitar resultados
python3 ui-ux-pro-max-skill/src/ui-ux-pro-max/scripts/search.py "QUERY" -n <n>
```

## Domínios Disponíveis
| Domínio | Descrição |
|---------|-----------|
| `product` | Recomendações por tipo de produto |
| `style` | Estilos UI (glassmorphism, minimalism, etc) |
| `typography` | Fontes e combinações tipográficas |
| `color` | Paletas de cores |
| `landing` | Estrutura de landing pages |
| `chart` | Tipos de gráficos |
| `ux` | Melhores práticas e anti-patterns |

## Stacks Suportados
- `flutter` (padrão para este projeto)
- `html-tailwind`
- `react`
- `nextjs`
- `vue`
- `swiftui`
- `react-native`
- `jetpack-compose`
- E mais...

## Exemplos

### Buscar estilo para app de delivery
```
python3 ui-ux-pro-max-skill/src/ui-ux-pro-max/scripts/search.py "delivery mobile" --domain style --stack flutter
```

### Buscar paleta de cores para e-commerce
```
python3 ui-ux-pro-max-skill/src/ui-ux-pro-max/scripts/search.py "e-commerce" --domain color
```

### Buscar UX guidelines para botões mobile
```
python3 ui-ux-pro-max-skill/src/ui-ux-pro-max/scripts/search.py "button mobile" --domain ux
```

### Buscar tipografia para app brasileiro
```
python3 ui-ux-pro-max-skill/src/ui-ux-pro-max/scripts/search.py "modern sans-serif" --domain typography
```

## Arquivos de Dados
- `data/styles.csv` - 67 estilos UI
- `data/colors.csv` - 161 paletas de cores
- `data/typography.csv` - 57 combinações tipográficas
- `data/ux-guidelines.csv` - 99 diretrizes UX
- `data/charts.csv` - 25 tipos de gráficos

## Aplicação no DiPertin
Ao criar novas telas, usar este comando para:
1. Selecionar estilo visual apropriado
2. Escolher paleta de cores consistente
3. Definir tipografia
4. Aplicar UX guidelines
5. Criar componentes acessíveis
