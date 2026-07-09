# Comando: /frontend-design

## Uso
`/frontend-design [descrição da tarefa]`

## Descrição
Comando especializado para criar e melhorar interfaces Flutter no projeto DiPertin,
aplicando as diretrizes do ui-ux-pro-max-skill.

## Quando Usar
- Criar novas telas
- Melhorar telas existentes
- Criar widgets reutilizáveis
- Implementar novos fluxos de UI
- Adicionar animações e transições
- Melhorar responsividade

## Processo

### 1. Analisar Contexto
- Ler arquivos existentes relacionados
- Identificar padrões de design usados
- Verificar componentes já disponíveis
- Consultar ui-ux-pro-max para sugestões

### 2. Planejar Implementação
- Criar lista de tarefas (TodoWrite)
- Definir estrutura de arquivos
- Planejar componentes necessários
- Estimar complexidade

### 3. Implementar
- Seguir estilo existente do projeto
- Usar constantes de cor definidas
- Manter consistência com código existente
- Aplicar práticas de acessibilidade
- Adicionar testes se necessário

### 4. Validar
- Verificar linting/formatting
- Garantir que compiles
- Revisar design com ui-ux-pro-max

## Exemplos de Uso
```
/frontend-design criar tela de checkout com forma de pagamento
/frontend-design melhorar tela de perfil do entregador
/frontend-design criar widget de card de produto
/frontend-design adicionar animação de skeleton loading
```

## Paleta de Cores do Projeto
```dart
const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);
const Color fundoTela = Color(0xFFF5F4F8);
const Color textoPrimario = Color(0xFF1A1A2E);
const Color textoMuted = Color(0xFF64748B);
```

## Estrutura de Pastas
- `lib/screens/cliente/` - Telas de cliente
- `lib/screens/lojista/` - Telas de lojista
- `lib/screens/entregador/` - Telas de entregador
- `lib/screens/comum/` - Telas compartilhadas
- `lib/widgets/` - Widgets reutilizáveis
