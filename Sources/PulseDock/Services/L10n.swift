import Foundation

/// Tiny localization layer: every UI string lives here as an English / Portuguese pair.
enum L10n {
    nonisolated(unsafe) static var language: String = "en"

    static var isPortuguese: Bool {
        switch language {
        case "pt": return true
        case "en": return false
        default:
            let pref = Locale.preferredLanguages.first ?? "en"
            return pref.hasPrefix("pt")
        }
    }

    static func t(_ key: String) -> String {
        guard let pair = strings[key] else { return key }
        return isPortuguese ? pair.1 : pair.0
    }

    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    static let strings: [String: (String, String)] = [
        // General
        "app.name": ("PulseDock", "PulseDock"),
        "overview": ("Overview", "Visão geral"),
        "memory": ("Memory", "Memória"),
        "processes": ("Processes", "Processos"),
        "cleanup": ("Cleanup", "Limpeza"),
        "settings": ("Settings", "Ajustes"),
        "open": ("Open PulseDock", "Abrir PulseDock"),
        "quit": ("Quit PulseDock", "Sair do PulseDock"),
        "settingsEllipsis": ("Settings…", "Ajustes…"),
        "cancel": ("Cancel", "Cancelar"),
        "close": ("Close", "Fechar"),
        "done": ("Done", "Concluído"),
        "search": ("Search", "Buscar"),
        "reveal": ("Show in Finder", "Mostrar no Finder"),

        // Metrics
        "cpu": ("CPU", "CPU"),
        "gpu": ("GPU", "GPU"),
        "disk": ("Disk", "Disco"),
        "network": ("Network", "Rede"),
        "battery": ("Battery", "Bateria"),
        "ram": ("RAM", "RAM"),
        "used": ("used", "em uso"),
        "free": ("free", "livre"),
        "of": ("of", "de"),
        "read": ("Read", "Leitura"),
        "write": ("Write", "Escrita"),
        "down": ("Down", "Download"),
        "up": ("Up", "Upload"),
        "cores": ("cores", "núcleos"),
        "perCore": ("Per core", "Por núcleo"),
        "load": ("Load average", "Carga média"),
        "uptime": ("Uptime", "Ligado há"),
        "thermal": ("Thermal state", "Estado térmico"),
        "thermal.nominal": ("Cool", "Normal"),
        "thermal.fair": ("Warm", "Morno"),
        "thermal.serious": ("Hot", "Quente"),
        "thermal.critical": ("Critical", "Crítico"),
        "pressure": ("Memory pressure", "Pressão de memória"),
        "pressure.normal": ("Normal", "Normal"),
        "pressure.warning": ("Elevated", "Elevada"),
        "pressure.critical": ("Critical", "Crítica"),
        "mem.app": ("App memory", "Memória de apps"),
        "mem.wired": ("Wired", "Fixa (wired)"),
        "mem.compressed": ("Compressed", "Comprimida"),
        "mem.cached": ("Cached files", "Arquivos em cache"),
        "mem.swap": ("Swap used", "Swap em uso"),
        "busy": ("busy", "ocupado"),
        "idle": ("idle", "ocioso"),
        "charging": ("Charging", "Carregando"),
        "onBattery": ("On battery", "Na bateria"),
        "pluggedIn": ("Plugged in", "Na tomada"),
        "remaining": ("%@ remaining", "%@ restantes"),
        "startupDisk": ("Startup disk", "Disco de inicialização"),

        // Processes / memory
        "topMemory": ("Using the most memory", "Consumindo mais memória"),
        "topCPU": ("Using the most CPU", "Consumindo mais CPU"),
        "topDisk": ("Using the most disk", "Mais ativos no disco"),
        "quitApp": ("Quit", "Encerrar"),
        "forceQuit": ("Force Quit", "Forçar encerramento"),
        "quitSelected": ("Quit %d selected", "Encerrar %d selecionados"),
        "quitConfirmTitle": ("Quit “%@”?", "Encerrar “%@”?"),
        "quitConfirmBody": ("Unsaved changes in this app may be lost. It frees about %@ of memory.", "Alterações não salvas neste app podem ser perdidas. Isso libera cerca de %@ de memória."),
        "forceConfirmBody": ("Force quitting closes the app immediately, without saving. It frees about %@.", "Forçar o encerramento fecha o app na hora, sem salvar. Libera cerca de %@."),
        "quitManyTitle": ("Quit %d apps?", "Encerrar %d apps?"),
        "quitManyBody": ("This frees about %@ of memory. Unsaved changes may be lost.", "Isso libera cerca de %@ de memória. Alterações não salvas podem ser perdidas."),
        "protected": ("Protected system process", "Processo de sistema protegido"),
        "groupByApp": ("Group by app", "Agrupar por app"),
        "processesCount": ("%d processes", "%d processos"),
        "name": ("Name", "Nome"),
        "pid": ("PID", "PID"),
        "readPerSec": ("Read/s", "Leitura/s"),
        "writePerSec": ("Write/s", "Escrita/s"),
        "onlyYours": ("Only your own processes are listed. System processes are protected and can't be closed.", "Somente os seus processos aparecem. Processos do sistema são protegidos e não podem ser fechados."),
        "freeUpMemory": ("Free up memory", "Liberar memória"),
        "freeUpHint": ("Select the apps you don't need right now and quit them in one click.", "Selecione os apps que você não precisa agora e encerre todos com um clique."),
        "quitFailed": ("Couldn't quit “%@”.", "Não foi possível encerrar “%@”."),
        "freed": ("Freed %@", "%@ liberados"),
        "memoryHog": ("%@ is using %@", "%@ está usando %@"),
        "sortBy": ("Sort by", "Ordenar por"),
        "background": ("Background", "Segundo plano"),

        // Cleanup
        "cleanup.title": ("Disk Cleanup", "Limpeza de disco"),
        "cleanup.subtitle": ("Find caches, logs and leftovers that are safe to remove.", "Encontre caches, logs e sobras que podem ser removidos com segurança."),
        "scan": ("Scan", "Analisar"),
        "rescan": ("Scan again", "Analisar de novo"),
        "scanning": ("Scanning…", "Analisando…"),
        "cleaning": ("Cleaning…", "Limpando…"),
        "cleanSelected": ("Clean %@", "Limpar %@"),
        "nothingToClean": ("Nothing selected", "Nada selecionado"),
        "cleanConfirmTitle": ("Clean %@?", "Limpar %@?"),
        "cleanConfirmBody": ("Caches, logs and build data are deleted (apps rebuild them as needed). Your own files are moved to the Trash.", "Caches, logs e dados de build são apagados (os apps os recriam quando precisam). Seus próprios arquivos vão para a Lixeira."),
        "cleanDone": ("Done — %@ freed.", "Pronto — %@ liberados."),
        "cleanPartial": ("%@ freed. %d items were in use or protected and were skipped.", "%@ liberados. %d itens estavam em uso ou protegidos e foram ignorados."),
        "needsAccess": ("Needs Full Disk Access", "Precisa de Acesso Total ao Disco"),
        "grantAccess": ("Grant access…", "Conceder acesso…"),
        "items": ("%d items", "%d itens"),
        "largeFiles": ("Large files", "Arquivos grandes"),
        "largeFilesHint": ("Files over 500 MB in your home folder. Review them before removing.", "Arquivos acima de 500 MB na sua pasta pessoal. Revise antes de remover."),
        "findLarge": ("Find large files", "Procurar arquivos grandes"),
        "moveToTrash": ("Move to Trash", "Mover para a Lixeira"),
        "noLargeFiles": ("No files over 500 MB found.", "Nenhum arquivo acima de 500 MB."),
        "reclaimable": ("Reclaimable", "Recuperável"),
        "safe": ("Safe", "Seguro"),
        "review": ("Review", "Revisar"),
        "lastCleaned": ("Last cleanup freed %@", "Última limpeza liberou %@"),

        "cat.caches": ("App caches", "Caches de apps"),
        "cat.caches.d": ("Temporary data apps keep to load faster. Rebuilt automatically.", "Dados temporários que os apps guardam para abrir mais rápido. São recriados sozinhos."),
        "cat.logs": ("Logs & crash reports", "Logs e relatórios de falha"),
        "cat.logs.d": ("Diagnostic logs written by apps and the system.", "Registros de diagnóstico gravados pelos apps e pelo sistema."),
        "cat.trash": ("Trash", "Lixeira"),
        "cat.trash.d": ("Files you already deleted. Emptying is permanent.", "Arquivos que você já apagou. Esvaziar é permanente."),
        "cat.derived": ("Xcode DerivedData", "DerivedData do Xcode"),
        "cat.derived.d": ("Build intermediates. Xcode rebuilds them on the next build.", "Arquivos intermediários de build. O Xcode recria no próximo build."),
        "cat.devicesupport": ("Old device support files", "Arquivos de suporte a dispositivos"),
        "cat.devicesupport.d": ("Debug symbols for iPhones/Watches connected in the past.", "Símbolos de depuração de iPhones/Watches conectados no passado."),
        "cat.simcaches": ("Simulator caches", "Caches do Simulador"),
        "cat.simcaches.d": ("Caches of the iOS Simulator runtime.", "Caches do runtime do Simulador iOS."),
        "cat.devcaches": ("Developer package caches", "Caches de pacotes de desenvolvimento"),
        "cat.devcaches.d": ("npm, Yarn, Gradle, pip and similar download caches.", "Caches de download do npm, Yarn, Gradle, pip e similares."),
        "cat.installers": ("Old installers in Downloads", "Instaladores antigos em Downloads"),
        "cat.installers.d": (".dmg, .pkg, .zip and .xip files older than 14 days. Moved to Trash.", "Arquivos .dmg, .pkg, .zip e .xip com mais de 14 dias. Vão para a Lixeira."),
        "cat.mail": ("Mail attachment downloads", "Anexos baixados do Mail"),
        "cat.mail.d": ("Copies of attachments you opened in Mail.", "Cópias de anexos que você abriu no Mail."),
        "cat.tmp": ("Temporary files", "Arquivos temporários"),
        "cat.tmp.d": ("Leftover temporary files older than 3 days.", "Sobras de arquivos temporários com mais de 3 dias."),

        // Settings
        "set.general": ("General", "Geral"),
        "set.language": ("Language", "Idioma"),
        "set.lang.auto": ("Automatic", "Automático"),
        "set.launchAtLogin": ("Open at login", "Abrir ao iniciar sessão"),
        "set.menuBar": ("Menu bar", "Barra de menus"),
        "set.mb.iconOnly": ("Icon only", "Só o ícone"),
        "set.mb.cpu": ("CPU", "CPU"),
        "set.mb.cpuMemory": ("CPU + Memory", "CPU + Memória"),
        "set.mb.full": ("CPU + Memory + Network", "CPU + Memória + Rede"),
        "set.widget": ("Widget", "Widget"),
        "set.mode": ("Mode", "Modo"),
        "mode.overlay": ("Floating (always on top)", "Flutuante (sempre na frente)"),
        "mode.desktop": ("On the desktop (behind windows)", "Na mesa (atrás das janelas)"),
        "mode.menuBarOnly": ("Menu bar only", "Só na barra de menus"),
        "set.layout": ("Layout", "Layout"),
        "layout.compact": ("Compact", "Compacto"),
        "layout.expanded": ("Full", "Completo"),
        "layout.strip": ("Strip", "Faixa"),
        "set.corner": ("Corner", "Canto"),
        "corner.topLeft": ("Top left", "Superior esquerdo"),
        "corner.topRight": ("Top right", "Superior direito"),
        "corner.bottomLeft": ("Bottom left", "Inferior esquerdo"),
        "corner.bottomRight": ("Bottom right", "Inferior direito"),
        "set.freePosition": ("Free position (dragged)", "Posição livre (arrastado)"),
        "set.screen": ("Display", "Monitor"),
        "set.mainScreen": ("Main display", "Monitor principal"),
        "set.margin": ("Distance from edge", "Distância da borda"),
        "set.opacity": ("Opacity", "Opacidade"),
        "set.lock": ("Lock position", "Travar posição"),
        "set.clickThrough": ("Click-through (hold ⌥ Option to interact)", "Ignorar cliques (segure ⌥ Option para interagir)"),
        "set.hideFullscreen": ("Hide when an app is full screen", "Ocultar quando um app estiver em tela cheia"),
        "set.metrics": ("Metrics", "Métricas"),
        "set.interval": ("Refresh every", "Atualizar a cada"),
        "set.seconds": ("%@ s", "%@ s"),
        "set.reset": ("Reset all settings", "Restaurar ajustes"),
        "set.about": ("About", "Sobre"),
        "set.version": ("Version %@", "Versão %@"),
        "set.resetPosition": ("Move widget back to its corner", "Voltar o widget para o canto"),
        "set.showWidget": ("Show widget", "Mostrar widget"),
        "set.hideWidget": ("Hide widget", "Ocultar widget"),
        "loginItemNote": ("Requires PulseDock to be in the Applications folder.", "Requer o PulseDock na pasta Aplicativos."),
    ]
}

/// Shorthand used across the UI.
func L(_ key: String) -> String { L10n.t(key) }
