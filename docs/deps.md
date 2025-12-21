```mermaid
graph TD
    %% --- Style Definitions ---
    classDef client fill:#e1f5fe,stroke:#01579b,stroke-width:2px;
    classDef server fill:#fce4ec,stroke:#880e4f,stroke-width:2px;
    classDef shared fill:#fff3e0,stroke:#e65100,stroke-width:2px;
    classDef package fill:#e8f5e9,stroke:#1b5e20,stroke-width:2px,stroke-dasharray: 5 5;

    %% --- Client Side (Blue) ---
    subgraph Client [Client Side]
        ClientInit[Init.client.lua]:::client
        UIController:::client
        InputController:::client
    end

    %% --- Server Side (Pink) ---
    subgraph Server [Server Side]
        ServerInit[Init.server.lua]:::server
        NetworkHandler:::server
        ProfileService:::server
        MonsterSpawnService:::server
    end

    %% --- Shared/Systems (Orange) ---
    subgraph Shared [ReplicatedStorage / Shared]
        EventBus:::shared
        Configs[GameConfigs]:::shared
    end

    %% --- Packages (Green) ---
    subgraph Packages [Wally Packages]
        Signal:::package
        Promise:::package
    end

    %% --- Relationships (Who requires Who?) ---
    
    %% Bootstrappers loading modules
    ClientInit -->|Requires| UIController
    ClientInit -->|Requires| InputController
    ServerInit -->|Requires| NetworkHandler
    ServerInit -->|Requires| MonsterSpawnService

    %% Controllers using Systems
    UIController -->|Requires| EventBus
    InputController -->|Emit| NetworkHandler
    
    %% Services using Systems
    NetworkHandler -->|Requires| EventBus
    MonsterSpawnService -->|Requires| EventBus

    %% Systems using Libraries
    EventBus -->|Requires| Signal
    
    %% Services using Libraries/Utils
    MonsterSpawnService -->|Uses| ProfileService
```