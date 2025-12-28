# Configuração do WhatsApp via Baileys no Chatwoot

Este guia descreve como configurar a integração do WhatsApp usando o provedor Baileys no Chatwoot.

## Pré-requisitos

A integração do Baileys no Chatwoot requer um serviço de API Baileys externo em execução. Este serviço atua como uma ponte entre o Chatwoot e os servidores do WhatsApp.

### 1. Serviço de API do Baileys

Você precisa ter um serviço de API compatível rodando. O Chatwoot espera que este serviço esteja acessível (por padrão em `http://localhost:3025`).

Se você ainda não tem esse serviço configurado, você precisará adicionar um container compatível ao seu `docker-compose.yaml`. Um exemplo comum é utilizar uma imagem de API baseada em Baileys.

**Exemplo de adição ao `docker-compose.yaml`:**

```yaml
services:
  baileys_api:
    image: whatsapp-api:latest # Substitua pela imagem da sua API Baileys preferida
    ports:
      - "3025:3025"
    environment:
      - PORT=3025
    restart: always
```

> **Nota:** Certifique-se de que a API que você escolher expõe os endpoints esperados pelo Chatwoot (`/connections`, `/connections/:phone/send-message`, etc.). Se você estiver usando uma solução como a Evolution API ou WPPConnect, pode ser necessário ajustar a URL ou usar um adaptador, pois os endpoints podem variar.

## Configuração do Ambiente (Backend)

No seu arquivo `.env` do Chatwoot, configure as variáveis para apontar para o seu serviço Baileys.

```bash
# Baileys API Whatsapp provider
BAILEYS_PROVIDER_DEFAULT_CLIENT_NAME=Chatwoot
BAILEYS_PROVIDER_DEFAULT_URL=http://baileys_api:3025 # Use o nome do serviço no docker-compose ou IP
BAILEYS_PROVIDER_DEFAULT_API_KEY=sua_chave_api_se_houver
```

*   **BAILEYS_PROVIDER_DEFAULT_URL**: A URL onde a API do Baileys está rodando. Se estiver rodando via Docker Compose na mesma rede, use o nome do serviço (ex: `http://baileys_api:3025`).
*   **BAILEYS_PROVIDER_DEFAULT_API_KEY**: A chave de API configurada no seu serviço Baileys (opcional, dependendo da configuração do serviço).

## Configuração no Chatwoot (Frontend)

Com o backend configurado, siga estes passos para adicionar a caixa de entrada no Chatwoot:

1.  Acesse o painel do Chatwoot como administrador.
2.  Vá para **Configurações** -> **Caixas de Entrada**.
3.  Clique em **Adicionar Caixa de Entrada**.
4.  Selecione **WhatsApp**.
5.  Na lista de provedores, escolha **Baileys**.
6.  Preencha os detalhes:
    *   **Nome da Caixa de Entrada**: Um nome para identificar este canal (ex: "WhatsApp Suporte").
    *   **Número de Telefone**: O número do WhatsApp no formato internacional (ex: `+5511999999999`).
7.  (Opcional) Clique em **Opções Avançadas** se precisar sobrescrever a URL ou API Key padrão configurada no `.env`.
8.  Clique em **Criar Caixa de Entrada**.

## Autenticação do QR Code

Após criar a caixa de entrada:

1.  Acesse a nova caixa de entrada criada.
2.  Dependendo da implementação da sua API Baileys, você deverá ver um código QR para escanear ou um status de conexão.
    *   *Geralmente, você precisará acessar os logs do serviço `baileys_api` ou uma interface específica dele para ler o QR Code inicial se ele não aparecer diretamente no Chatwoot.*
3.  Abra o WhatsApp no seu celular, vá em **Dispositivos Conectados** e escaneie o QR Code.

### Solução de Problemas

*   **Erro de Conexão**: Verifique se o container `baileys_api` está rodando e se a URL no `.env` está correta. Teste a conexão com `curl http://localhost:3025/status`.
*   **Mensagens não enviadas**: Verifique os logs do Sidekiq no Chatwoot para erros de envio. Confirme se a API Key está correta.
