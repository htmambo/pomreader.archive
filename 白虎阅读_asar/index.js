const {app, BrowserWindow, Menu} = require('electron');
const path = require('path');
const url = require('url');

// Wayland 下 KDE 用 app_id 匹配 .desktop 文件获取图标和名称，
// 必须与已安装的 pomreader.desktop 文件名一致
app.setDesktopName('pomreader');

function createWindow() {
    let win = new BrowserWindow({
        width: 1400,
        height: 850,
        webPreferences: {
            nodeIntegration: true,
            contextIsolation: false,
            webSecurity: false,
            webviewTag: true,
        }
    });
    win.setMenuBarVisibility(false)
    win.loadURL(url.format({
        pathname: path.join(__dirname, 'app/index.prod.html'),
        protocol: 'file:',
        slashes: true
    }))
    // win.webContents.openDevTools();
}

var template = [{
    label: "Application",
    submenu: [
        {label: "About Application", selector: "orderFrontStandardAboutPanel:"},
        {type: "separator"},
        {
            label: "Quit", accelerator: "Command+Q", click: function () {
                app.quit();
            }
        },
        {
            label: "Quit Window", accelerator: "Command+W", click: function () {
                app.quit();
            }
        }
    ]
}, {
    label: "Edit",
    submenu: [
        {label: "Undo", accelerator: "CmdOrCtrl+Z", selector: "undo:"},
        {label: "Redo", accelerator: "Shift+CmdOrCtrl+Z", selector: "redo:"},
        {type: "separator"},
        {label: "Cut", accelerator: "CmdOrCtrl+X", selector: "cut:"},
        {label: "Copy", accelerator: "CmdOrCtrl+C", selector: "copy:"},
        {label: "Paste", accelerator: "CmdOrCtrl+V", selector: "paste:"},
        {label: "Select All", accelerator: "CmdOrCtrl+A", selector: "selectAll:"}
    ]
}];

// 单实例锁：dev 版与 pacman 安装版共享 ~/.config/pom-reader-desktop，
// 双实例会争用 IndexedDB 导致写入失败甚至数据丢失
if (!app.requestSingleInstanceLock()) {
    app.quit();
} else {
    app.on('second-instance', () => {
        const win = BrowserWindow.getAllWindows()[0];
        if (win) {
            if (win.isMinimized()) win.restore();
            win.focus();
        }
    });
}

// Electron >= 22 移除了 webview 的 new-window 事件，
// 用 setWindowOpenHandler 复刻原来的"页内跳转"行为
app.on('web-contents-created', (event, contents) => {
    if (contents.getType() === 'webview') {
        contents.setWindowOpenHandler(({url}) => {
            contents.loadURL(url);
            return {action: 'deny'};
        });
    }
});

app.on('ready', createWindow);
app.on('ready', () => {
    Menu.setApplicationMenu(Menu.buildFromTemplate(template));
});

app.on('window-all-closed', () => app.quit());