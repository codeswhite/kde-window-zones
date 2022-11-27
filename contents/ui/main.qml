import QtGraphicalEffects 1.0
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.2
import org.kde.kirigami 2.5 as Kirigami
import org.kde.kwin 2.0
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.plasma.core 2.0 as PlasmaCore

import "components" as Components

PlasmaCore.Dialog {

    id: mainDialog
    location: PlasmaCore.Types.Desktop // on the planar desktop layer, extending across the full screen from edge to edge. 
    backgroundHints: PlasmaCore.Types.NoBackground // not drawing a background under the applet, the applet has its own implementation. 
    flags: Qt.X11BypassWindowManagerHint | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    visible: false // hide dialog on startup
    opacity: 0 // hide dialog on startup
    outputOnly: true // makes dialog click-through

    // properties
    property var config: {}
    property bool shown: false
    property bool moving: false
    property bool resizing: false
    property var clientArea: {}
    property var cachedClientArea: {}
    property int currentLayout: 0
    property int highlightedZone: -1
    property int activeScreen: 0
    property bool doAnimations: true
    property var modifierKeys: ["Alt", "AltGr", "Ctrl", "Hyper", "Meta", "Shift", "Super"]

    // colors
    property string color_zone_border: "transparent"
    property string color_zone_border_active: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.9)
    property string color_zone_background: "transparent"
    property string color_zone_background_active: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.1)
    property string color_indicator: Qt.rgba(Kirigami.Theme.alternateBackgroundColor.r, Kirigami.Theme.alternateBackgroundColor.g, Kirigami.Theme.alternateBackgroundColor.b, 1) //'#66555555'
    property string color_indicator_accent: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 1)
    property string color_indicator_shadow: '#69000000'
    property string color_indicator_font: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 1)
    property string color_debug_handle: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.9)  

    function loadConfig() {
        // load values from configuration
        console.log("KZones: Reading config...")

        config = {
            rememberWindowGeometries: KWin.readConfig("rememberWindowGeometries", true), // remember window geometries before snapping to a zone, and restore them when the window is removed from their zone
            alwaysShowLayoutName: KWin.readConfig("alwaysShowLayoutName", false), // always show layout name, or only when switching between them
            pollingRate: KWin.readConfig("pollingRate", 100), // polling rate in milliseconds
            zoneTarget: KWin.readConfig("zoneTarget", 0), // the part of the zone you need to hover over to highlight it
            zoneMatchOrigin: KWin.readConfig("zoneMatchOrigin", 0), // geometric position origin when determining in which zone the window is located
            zoneMatchMethod: KWin.readConfig("zoneMatchMethod", 0), // method to determine in which zone the window is located
            handleUnitPercent: KWin.readConfig("handleUnitPercent", true), // method to determine in which zone the window is located
            handleUnitPixels: KWin.readConfig("handleUnitPixels", false), // method to determine in which zone the window is located (unused)
            handleSize: KWin.readConfig("handleSize", 100), // set the size of the handle, only applicable when target method is Titlebar or Window
            enableDebugMode: KWin.readConfig("enableDebugMode", false), // enable debug mode
            filterMode: KWin.readConfig("filterMode", 0), // filter mode
            filterList: KWin.readConfig("filterList", ""), // filter list
            fadeDuration: KWin.readConfig("fadeDuration", 100), // animation duration in milliseconds
            osdTimeout: KWin.readConfig("osdTimeout", 1000), // timeout in milliseconds for hiding the OSD after switching layouts
            layouts: JSON.parse(KWin.readConfig("layoutsJson", '[{"name": "Layout 1","padding": 0,"zones": [{"name": "1","x": 0,"y": 0,"height": 100,"width": 25},{"name": "2","x": 25,"y": 0,"height": 100,"width": 50},{"name": "3","x": 75,"y": 0,"height": 100,"width": 25}]}]')), // layouts
            alternateIndicatorStyle: KWin.readConfig("alternateIndicatorStyle", false), // alternate indicator style
            invertedMode: KWin.readConfig("invertedMode", false), // inverted mode
            modifierEnabled: KWin.readConfig("modifierEnabled", false), // modifier enabled
            modifierKey: KWin.readConfig("modifierKey", 5), // modifier key
            npmbEnabled: KWin.readConfig("npmbEnabled", false), // npmb enabled
            npmbToggle: KWin.readConfig("npmbToggle", true), // toggle with non-primary mouse button
            npmbCycle: KWin.readConfig("npmbCycle", false), // cycle layouts with non-primary mouse button
        }

        console.log("KZones: Config loaded: " + JSON.stringify(config))
    }

    function toggleOsd(isShow) {
        if (!isShow) {   
            // Hide OSD
            mainDialog.opacity = 0
            mainDialog.shown = false
            mainDialog.outputOnly = true
            mainItem.width = 0
            mainItem.height = 0
            return
        }

        // show OSD
        if (!config.alwaysShowLayoutName) layoutOsd.visible = false

        // refresh client area
        refreshClientArea()

        // update main item size (needed for boot time, and to reset after hiding)
        mainItem.width = workspace.displayWidth
        mainItem.height = workspace.displayHeight

        if (!mainDialog.shown) {
            mainDialog.outputOnly = false
            mainDialog.opacity = 1
            mainDialog.shown = true
            highlightedZone = -1
        }
    }

    function refreshClientArea() {
        activeScreen = workspace.activeScreen
        clientArea = workspace.clientArea(KWin.FullScreenArea, workspace.activeScreen, workspace.currentDesktop)
    }

    function getZoneGeometry(zone_idx) {
        let zone
        switch (config.zoneTarget) {
            case 0:
                zone = repeater_zones.itemAt(zone_idx).children[0]
                break
            case 1:
                zone = repeater_zones.itemAt(zone_idx)
                break
        }
        const zoneItem = zone.mapToItem(null, 0, 0)
        return {
            "x": zoneItem.x,
            "y": zoneItem.y,
            "width": zone.width,
            "height": zone.height
        }
    }

    function checkZone(x, y, width = 1, height = 1) {
        let closest = {'distance': 999999, 'zone': -1}
        let most_overlapping = {'area': 0, 'zone': -1}
        const inputRect = {
            "x": x,
            "y": y,
            "width": width,
            "height": height
        }

        for (let idx = 0; idx < repeater_zones.model.length; idx++) {
            const zoneGeo = getZoneGeometry(idx)
            const overlap = rectOverlapArea(zoneGeo, inputRect)
            if (overlap === 0) {
                continue
            }

            if (overlap > most_overlapping.area) {
                most_overlapping = { 'area': overlap, 'zone': idx }
            }
            const xDist = Math.abs((x + width / 2) - (zoneGeo.x + zoneGeo.width / 2))
            const yDist = Math.abs((y + height / 2) - (zoneGeo.y + zoneGeo.height / 2))
            const distance = xDist + yDist
            if (distance < closest.distance) {
                closest = { 'distance': distance, 'zone': idx }
            }
        }

        // console.log("KZone: [zone check] closest: ", JSON.stringify(closest))
        // console.log("KZone: [zone check] most_overlapping: ", JSON.stringify(most_overlapping))
        switch (config.zoneMatchMethod) {
            default:
            case 0: // Closest distance
                return closest.zone
            case 1: // Most area overlap
                return most_overlapping.zone
        }
        return -1
    }

    function checkZoneByGeometry(geometry) {
        return checkZone(geometry.x, geometry.y, geometry.width, geometry.height)
    }

    function resetAllClientZones() {
        for (var i = 0; i < workspace.clientList().length; i++) {
            workspace.clientList()[i].zone = -1
        }
    }

    function switchWindowInZone(isReverse) {
        // Check active client's zone
        const activeClientZone = workspace.activeClient.zone
        console.log(activeClientZone)
        if (activeClientZone === -1) {
            // If the client is not in any zone then we should assign it to a zone
            return moveClientToZone()
        }

        // Get all clients in the active zone
        const clientsInZone = Object.values(workspace.clientList())
            .filter(function(w) { return w.normalWindow && w.zone === activeClientZone })
        if (!clientsInZone.length) return;

        if (isReverse) { clientsInZone.reverse() }

        // cycle through clients in zone
        const index = clientsInZone.indexOf(workspace.activeClient)
        workspace.activeClient = clientsInZone[(index + 1) % clientsInZone.length]
    }

    function rectOverlapArea(component1, component2) {
        let x1 = component1.x + clientArea.x
        let y1 = component1.y + clientArea.y
        let x2 = component1.x + component1.width + clientArea.x
        let y2 = component1.y + component1.height + clientArea.y
        let x3 = component2.x + clientArea.x
        let y3 = component2.y + clientArea.y
        let x4 = component2.x + component2.width + clientArea.x
        let y4 = component2.y + component2.height + clientArea.y
        let xOverlap = Math.max(0, Math.min(x2, x4) - Math.max(x1, x3))
        let yOverlap = Math.max(0, Math.min(y2, y4) - Math.max(y1, y3))
        return xOverlap * yOverlap
    }

    function moveClientToZone(zone = checkZoneByGeometry(workspace.activeClient.geometry), client = workspace.activeClient) {
        // Hide when assigning to zone
        // TODO: configurable: "Checkbox: Hide OSD when assigning to zone"
        toggleOsd(false)

        // block abnormal windows from being moved (like plasmashell, docks, etc...)
        if (!client.normalWindow) return
        if (zone === -1) {
            console.log("[!!] Attempted to move client to zone '-1' .. Its likely a bug :(")
            return
        }

        const zonesLength = config.layouts[currentLayout].zones.length
        if (zone > zonesLength) return

        console.log("KZones: Moving client " + client.resourceClass.toString() + " to zone " + zone)

        if (client.zone === -1 && config.rememberWindowGeometries) {
            // Save client geometry before moving to a zone
            saveWindowGeometries(client)
        }

        // Set new geometry and zone
        let repeater_zone = repeater_zones.itemAt(zone)
        let global_x = repeater_zone.mapToGlobal(Qt.point(0, 0)).x
        let global_y = repeater_zone.mapToGlobal(Qt.point(0, 0)).y
        let newGeometry = Qt.rect(Math.round(global_x), Math.round(global_y), Math.round(repeater_zone.width), Math.round(repeater_zone.height))
        console.log("KZones: Moving client " + client.resourceClass.toString() + " to zone " + zone + " with new geometry " + JSON.stringify(newGeometry))
        client.geometry = newGeometry
        client.zone = zone
    } 

    function saveWindowGeometries(client) {
        console.log("KZones: Saving geometry for client " + client.resourceClass.toString())
        // save current geometry
        client.oldGeometry = {
            "x": client.geometry.x,
            "y": client.geometry.y,
            "width": client.geometry.width,
            "height": client.geometry.height
        }
    }

    Behavior on opacity {
        NumberAnimation { 
            duration: config.fadeDuration
            onRunningChanged: {
                mainDialog.visible = true //running || shown
            }
        }
    }

    Component.onCompleted: {

        // register window
        KWin.registerWindow(mainDialog)

        // refresh client area
        refreshClientArea()        
        // shortcut: cycle through layouts
        bindShortcut("Cycle layouts", "Ctrl+Alt+D", function() {
            // reset timer to prevent osd from being hidden when switching layouts
            if (!moving) {
                hideOSD.running = false
                // if (!config.keepOsdAfterLayoutSwitch) // TODO: config: "Checkbox (default false): Keep OSD open after switching layouts"
                hideOSD.start()
            }

            //cycle through layouts
            currentLayout = (currentLayout + 1) % config.layouts.length

            // Reset zones of clients
            resetAllClientZones()

            highlightedZone = -1
            toggleOsd(true)
            if (!config.alwaysShowLayoutName) layoutOsd.visible = true
        })

        // shortcut: move to zone (1-9)
        for (let zone_idx = 0; zone_idx < 9; zone_idx++) {
            bindShortcut(`Move active window to zone ${zone_idx+1}`, `Ctrl+Alt+Num+${zone_idx+1}`, function() {
                moveClientToZone(zone_idx)
            })
        }

        function cycleActiveClient(isForward) {
            const activeZone = workspace.activeClient.zone
            if (activeZone === -1) {
                moveClientToZone()
                return
            }
            const zonesLength = config.layouts[currentLayout].zones.length
            const nextZone = isForward 
                ? (activeZone + 1) % zonesLength
                : (activeZone - 1 + zonesLength) % zonesLength
            moveClientToZone(nextZone)
        }

        // shortcut: move to next zone
        bindShortcut("Move active window to next zone", "Ctrl+Alt+Right", function() {
            cycleActiveClient(true)
        })
        // shortcut: move to previous zone
        bindShortcut("Move active window to previous zone", "Ctrl+Alt+Left", function() {
            cycleActiveClient(false)
        })

        // shortcut: toggle osd
        bindShortcut("Toggle OSD", "Ctrl+Alt+C", function() {
            toggleOsd(!shown)
        })

        // shortcut: switch to next window in current zone
        bindShortcut("Switch to next window in current zone", "Ctrl+Alt+Up", function() {
            switchWindowInZone(false)
        })

        // shortcut: switch to previous window in current zone
        bindShortcut("Switch to previous window in current zone", "Ctrl+Alt+Down", function() {
            switchWindowInZone(true)
        })

        mainDialog.loadConfig()

        // set all windows to be without a zone
        resetAllClientZones()

        //get session type
        cmdSessionType.exec()

        // delay the initialization of the overlay until the workspace is ready
        delay.setTimeout(function() {
            mainDialog.visible = true
            mainDialog.opacity = 0
            console.log("KZones: Ready!")
        }, 1000)
    }

    function bindShortcut(title, sequence, callback) {
        KWin.registerShortcut(`KZones: ${title}`, `KZones: ${title}`, sequence, callback)
    }

    Item {
        id: mainItem
        width: workspace.displayWidth
        height: workspace.displayHeight

        // main polling timer
        Timer {
            id: timer
            triggeredOnStart: true
            interval: config.pollingRate
            running: shown && moving
            repeat: true

            onTriggered: {
                switch (config.zoneMatchOrigin) {
                case 0: // titlebar
                    const clientGeo = workspace.activeClient.geometry
                    highlightedZone = checkZone(clientGeo.x, clientGeo.y, clientGeo.width, 1)
                    break;
                case 1: // window (center of window)
                    highlightedZone = checkZoneByGeometry(workspace.activeClient.geometry)
                    break
                case 2: // cursor
                    let pos = mouseSource.getPosition()
                    highlightedZone = checkZone(pos.x, pos.y)
                    break
                default:
                    break
                }
            }
        }

        PlasmaCore.DataSource {
            id: mouseSource

            property var position: null

            function getPosition() {
                mouseSource.connectSource("Position")
                return position
            }

            onNewData: {
                position = mouseSource.data.Position.Position
                disconnectSource(sourceName);   
            }
        }

        PlasmaCore.DataSource {
            id: keystateSource
            engine: "keystate"
            connectedSources: {
                let sources = []
                if (config.npmbEnabled) {
                    sources = sources.concat(["Left Button", "Right Button", "Middle Button"])
                }
                if (config.modifierEnabled) {
                    sources.push(modifierKeys[config.modifierKey])
                }
                return sources
            }
            // ["Shift","Right Button","First X Button","Caps Lock","Middle Button","Alt","Num Lock","Left Button","Meta","AltGr","Second X Button","Hyper","Ctrl","Super"]
            onNewData: {
                //console.log(JSON.stringify(keystateSource))
                //console.log(sourceName)
                if (moving) {
                    switch (sourceName) {
                        case modifierKeys[config.modifierKey]:
                            const pressed = keystateSource.data[sourceName].Pressed
                            console.log("KZones: Modifier key ", pressed ? 'Pressed' : 'Released')
                            toggleOsd(pressed === config.invertedMode)
                            break
                        case "Left Button":
                        case "Right Button":
                        case "Middle Button":
                            if(keystateSource.data[sourceName].Pressed) {
                                console.log("KZones: Npmb pressed")
                                if (config.npmbToggle) {
                                    toggleOsd(!shown)
                                }
                                if (config.npmbCycle) {
                                    highlightedZone = -1
                                    currentLayout = (currentLayout + 1) % config.layouts.length
                                }                    
                            }
                            break
                    }               
                }
            }
        }

        PlasmaCore.DataSource {
            id: osdCmd
            engine: "executable"
            connectedSources: []
            onNewData: {
                disconnectSource(sourceName);
            }
            function exec(text) {
                connectSource(`qdbus org.kde.plasmashell /org/kde/osdService showText preferences-desktop-virtual "${text}"`);
            }
        }

        PlasmaCore.DataSource {
            id: cmdSessionType
            engine: "executable"
            connectedSources: []
            onNewData: {
                let session = cmdSessionType.data[cmdSessionType.connectedSources[0]].stdout.trim()
                if (session == "x11") {
                    console.log("KZones: X11 session detected")
                    //when this is set in Wayland, KWin crashes 🤦
                    mouseSource.engine = "mouse"
                } else {
                    console.log("KZones: Wayland session detected")
                }
                disconnectSource(sourceName);
            }
            function exec() {
                connectSource(`echo $XDG_SESSION_TYPE`);
            }
        }

        // click to exit osd
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPressed: {
                toggleOsd(false)
            }
        }

        // debug handle
        Rectangle {
            id: handle
            color: color_debug_handle
            visible: config.enableDebugMode
            width: {
                if (config.targetMethod == 0 || config.targetMethod == 1) {
                    return (config.handleUnitPercent) ? workspace.activeClient.width * (config.handleSize / 100) : config.handleSize
                }
                else {
                    return 32
                }
            }
            height: {
                if (config.targetMethod == 0) {
                    let titlebarHeight = workspace.activeClient.rect.height - workspace.activeClient.clientSize.height
                    return titlebarHeight > 0 ? titlebarHeight : 32
                }
                else if (config.zoneMatchOrigin == 1) {
                    return (config.handleUnitPercent) ? workspace.activeClient.height * (config.handleSize / 100) : config.handleSize
                } else {
                    return 32
                }
            }
            x: {
                if (config.targetMethod == 0) {
                    return workspace.activeClient.geometry.x + (workspace.activeClient.geometry.width / 2) - (handle.width / 2)
                }
                else if (config.zoneMatchOrigin == 1) {
                    let centerpadding_width = (config.handleUnitPercent) ? workspace.activeClient.width * (config.handleSize / 100) : config.handleSize
                    return ((workspace.activeClient.x + workspace.activeClient.width / 2)) - centerpadding_width / 2
                } else {
                    return mouseSource.position.x - handle.width / 2  || 0
                }
            }
            y: {
                if (config.targetMethod == 0) {
                    return workspace.activeClient.geometry.y
                }
                else if (config.zoneMatchOrigin == 1) {
                    let centerpadding_height = (config.handleUnitPercent) ? workspace.activeClient.height * (config.handleSize / 100) : config.handleSize
                    return ((workspace.activeClient.y + workspace.activeClient.height / 2)) - centerpadding_height / 2
                } else {
                    return mouseSource.position.y - handle.height / 2  || 0
                }
            }
        }

        // debug osd
        Rectangle {
            id: debugOsd
            visible: config.enableDebugMode
            x: clientArea.x
            y: clientArea.y
            z: 100
            width: debugOsdText.paintedWidth + debugOsdText.padding * 2
            height: debugOsdText.paintedHeight + debugOsdText.padding * 2
            radius: 5
            color: "#DD333333"

            Text {
                id: debugOsdText
                anchors.fill: parent
                padding: 15
                color: 'white'
                text: {
                    if (config.enableDebugMode) {
                        let t = ""
                        t += `Active: ${workspace.activeClient.caption}\n`
                        t += `Window class: ${workspace.activeClient.resourceClass.toString()}\n`
                        t += `X: ${workspace.activeClient.geometry.x}, Y: ${workspace.activeClient.geometry.y}, Width: ${workspace.activeClient.geometry.width}, Height: ${workspace.activeClient.geometry.height}\n`
                        t += `Previous Zone: ${workspace.activeClient.zone}\n`
                        t += `Highlighted Zone: ${highlightedZone}\n`
                        t += `Layout: ${currentLayout}\n`
                        t += `Zones: ${config.layouts[currentLayout].zones.map(z => z.name).join(', ')}\n`
                        t += `Polling Rate: ${config.pollingRate}ms\n`
                        t += `Handle X: ${handle.x}, Y: ${handle.y}, Width: ${handle.width}, Height: ${handle.height}\n`
                        t += `Moving: ${moving}\n`
                        t += `Resizing: ${resizing}\n`
                        t += `Old Geometry: ${JSON.stringify(workspace.activeClient.oldGeometry)}\n`
                        t += `Active Screen: ${activeScreen}`
                        return t
                    } else {
                        return ""
                    }                 
                }
                font.pixelSize: 14
                font.family: "Hack"
            }
        }

        // layout name
        Rectangle {
            id: layoutOsd
            visible: true
            opacity: config.layouts[currentLayout].name ? 1 : 0
            x: clientArea.x + clientArea.width / 2 - width / 2
            y: clientArea.y + clientArea.height - 150
            width: layoutName.paintedWidth + 30
            height: layoutName.paintedHeight + 15
            radius: 5
            color: color_indicator

            // layout name label
            Text {
                id: layoutName
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: 'white'
                text: config.layouts[currentLayout].name
                font.pixelSize: 24
            }
        }

        // zones
        Repeater {
            id: repeater_zones
            model: config.layouts[currentLayout].zones

            // zone
            Rectangle {
                id: zone
                x: clientArea.x + ((modelData.x / 100) * (clientArea.width - zone_padding)) + zone_padding
                y: clientArea.y + ((modelData.y / 100) * (clientArea.height - zone_padding)) + zone_padding
                implicitWidth: ((modelData.width / 100) * (clientArea.width - zone_padding)) - zone_padding
                implicitHeight: ((modelData.height / 100) * (clientArea.height - zone_padding)) - zone_padding
                color: (highlightedZone == zoneIndex) ? color_zone_background_active : color_zone_background
                radius: 8 // TODO: make configurable (zoneRadius)
                border.color: (highlightedZone == zoneIndex) ? color_zone_border_active : color_zone_border
                border.width: 3

                property int zoneIndex: index
                property int zone_padding: config.layouts[currentLayout].padding || 0

                //! keep this the first child
                Rectangle {
                    id: indicator
                    width: 160 //180 // TODO: make configurable (indicatorWidth)
                    height: 90 //100 // TODO: make configurable (indicatorHeight)
                    radius: 5
                    color: config.alternateIndicatorStyle ? color_indicator : 'transparent'
                    opacity: (highlightedZone != zone.zoneIndex) ? 1.0 : 0.5
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        horizontalCenterOffset: (((modelData || {}).indicator || {}).offset || {}).x || 0
                        verticalCenter: parent.verticalCenter
                        verticalCenterOffset: (((modelData || {}).indicator || {}).offset || {}).y || 0
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: {
                            moveClientToZone(zone.zoneIndex)
                        }
                        onEntered: {
                            highlightedZone = zone.zoneIndex
                        }
                        onExited: {
                            if (shown) highlightedZone = -1
                        }
                    }

                    // zone indicator part
                    Repeater {
                        id: indicators
                        model: config.layouts[currentLayout].zones

                        Rectangle {
                            property int padding: config.alternateIndicatorStyle ? 0 : 3
                            radius: 5
                            visible: config.alternateIndicatorStyle ? ((index == zone.zoneIndex) ? true : false) : true
                            x: ((modelData.x / 100) * (indicator.width - padding)) + padding
                            y: ((modelData.y / 100) * (indicator.height - padding)) + padding
                            z: (index == zone.zoneIndex) ? 2 : 1
                            implicitWidth: ((modelData.width / 100) * (indicator.width - padding)) - padding
                            implicitHeight: ((modelData.height / 100) * (indicator.height - padding)) - padding
                            color: (index == zone.zoneIndex) ? color_indicator_accent : color_indicator
                            // opacity: (highlightedZone != zone.zoneIndex) ? 1.0 : 1.0 // TODO: add opacity to config
                            scale: (doAnimations) ? ((highlightedZone == zone.zoneIndex) ? ((index == zone.zoneIndex) ? 1.1 : 1) : 1.0) : 1
                            Behavior on scale {
                                NumberAnimation { duration: 150 }
                            }
                        }
                    }

                    // zone indicator label
                    Text {
                        z: 3
                        anchors.fill: indicator
                        font.pixelSize: 20
                        opacity: (highlightedZone != zone.zoneIndex) ? 1.0 : 0.5 // TODO: add opacity to config
                        color: color_indicator_font
                        leftPadding: 30
                        rightPadding: 30
                        topPadding: 30
                        bottomPadding: 30
                        fontSizeMode: Text.Fit
                        minimumPixelSize: 8
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: modelData.name
                    }
                }

                // zone indicator shadow
                Components.Shadow{
                    target: indicator
                }

            }

        }

        // workspace connection
        Connections {
            target: workspace
            
            function onClientAdded(client) {
                if (client.normalWindow) {
                    client.zone = -1
                }
            }

            function onClientFullScreenSet(client, fullscreen, user) {
                if (!client) return;
                console.log("KZones: Client fullscreen: " + client.resourceClass.toString() + " (fullscreen " + fullscreen + ")");
                toggleOsd(false)
            }


            function onClientActivated(client) {
                if (client) {
                    console.log("KZones: Client activated: " + client.resourceClass.toString() + " (zone " + client.zone + ")");
                    refreshClientArea();
                }    
            }

            // unused, but may be useful in the future
            // function onVirtualScreenSizeChanged(){ }
        }

        // options connection
        Connections {
            //! not working at the moment
            target: options

            function onConfigChanged() {
                console.log("KZones: Config changed")
                mainDialog.loadConfig()
            }
        }

        // activeClient connection
        Connections {
            target: workspace.activeClient

            // start moving
            function onClientStartUserMovedResized(client) {
                if (client.resizeable && client.normalWindow) {
                    client.zone = -1
                    console.log("KZones: Active client move/restart begin: " + client.resourceClass.toString())
                    if (client.move && checkFilter(client)) {
                        refreshClientArea()
                        moving = true
                        resizing = false
                        hideOSD.running = false

                        if (client.oldGeometry) {
                            console.log("KZones: Restoring old geometry")
                            client.geometry.x = client.oldGeometry.x
                            client.geometry.y = client.oldGeometry.y
                            client.geometry.width = client.oldGeometry.width
                            client.geometry.height = client.oldGeometry.height
                            delete client.oldGeometry
                        }
                    }
                    if (client.resize) {
                        moving = false
                        resizing = true
                        // client resizing
                    }
                }
            }

            // is moving
            function onClientStepUserMovedResized(client, r) {
                refreshClientArea();
            }

            // stop moving
            function onClientFinishUserMovedResized(client) {
                if (moving) {
                    console.log("Kzones: Move end " + client.resourceClass.toString())
                    if (shown) {
                        moveClientToZone(highlightedZone, client)
                    }
                }
                if (resizing) {
                    // client resizing
                }
                moving = false
                resizing = false
            }

            // check filter
            function checkFilter(client) {

                let filter = config.filterList.split(/\r?\n/)

                if (config.filterList.length > 0) {
                    if (config.filterMode == 0) { // include
                        return filter.includes(client.resourceClass.toString())
                    }
                    if (config.filterMode == 1) { // exclude
                        return !filter.includes(client.resourceClass.toString())
                    }
                }
                return true
            }
        }

        // hide osd timer
        Timer {
            id: hideOSD
            interval: config.osdTimeout
            repeat: false

            onTriggered: {
                toggleOsd(false)
            }
        }

        // reusable timer
        Timer {
            id: delay

            function setTimeout(callback, timeout) {
                delay.interval = timeout
                delay.repeat = false
                delay.triggered.connect(callback)
                delay.triggered.connect(function release () {
                    delay.triggered.disconnect(callback)
                    delay.triggered.disconnect(release)
                })
                delay.start()
            }
        }

    }

}