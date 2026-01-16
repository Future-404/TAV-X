const { execSync, spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

const env = require('../../core/env');
const ui = require('../../core/ui');

/**
 * SillyTavern Configuration Manager
 */

const ST_DIR = env.getAppPath('sillytavern');
const CONFIG_FILE = path.join(ST_DIR, 'config.yaml');
const MEMORY_CONF = path.join(env.getAppPath('tav_x'), 'config', 'memory.conf');

// 尝试从 SillyTavern 目录加载 YAML 库
let YAML;
try {
    YAML = require(path.join(ST_DIR, 'node_modules', 'yaml'));
} catch (e) {
    try {
        // Fallback: 尝试加载 js-yaml (部分旧版本 ST 可能使用)
        YAML = require(path.join(ST_DIR, 'node_modules', 'js-yaml'));
        // 适配 js-yaml 接口差异
        if (!YAML.parse) YAML.parse = YAML.load;
        if (!YAML.stringify) YAML.stringify = YAML.dump;
    } catch (ex) {
        ui.print('error', '致命错误: 无法加载 YAML 解析库。请确保 SillyTavern 已正确安装依赖 (npm install)。');
        process.exit(1);
    }
}

// --- 帮助函数 ---
// ... (保持现有代码不变)

// 读取内存配置
function getMemoryLimit() {
    try {
        if (fs.existsSync(MEMORY_CONF)) {
            const val = fs.readFileSync(MEMORY_CONF, 'utf8').trim();
            if (val && !isNaN(val)) return parseInt(val);
        }
    } catch (e) {}
    return 0; // 0 表示默认/自动
}

// 写入内存配置
function setMemoryLimit(val) {
    try {
        const confDir = path.dirname(MEMORY_CONF);
        if (!fs.existsSync(confDir)) fs.mkdirSync(confDir, { recursive: true });
        
        if (val === 0 || val === '0') {
            if (fs.existsSync(MEMORY_CONF)) fs.unlinkSync(MEMORY_CONF);
        } else {
            fs.writeFileSync(MEMORY_CONF, String(val));
        }
    } catch (e) {
        ui.print('error', `保存内存配置失败: ${e.message}`);
    }
}

function loadConfig() {
// ...
    try {
        if (!fs.existsSync(CONFIG_FILE)) return {};
        const content = fs.readFileSync(CONFIG_FILE, 'utf8');
        return YAML.parse(content) || {};
    } catch (e) {
        ui.print('error', '读取配置文件失败');
        return {};
    }
}

function saveConfig(configObj) {
    try {
        const content = YAML.stringify(configObj);
        fs.writeFileSync(CONFIG_FILE, content, 'utf8');
        return true;
    } catch (e) {
        ui.print('error', '保存配置文件失败');
        return false;
    }
}

function getNestedValue(obj, path) {
    return path.split('.').reduce((prev, curr) => (prev ? prev[curr] : undefined), obj);
}

function setNestedValue(obj, path, value) {
    const keys = path.split('.');
    const lastKey = keys.pop();
    const target = keys.reduce((prev, curr) => {
        if (!prev[curr]) prev[curr] = {};
        return prev[curr];
    }, obj);
    target[lastKey] = value;
}

function stConfigGet(key, defaultValue = '') {
    const config = loadConfig();
    const val = getNestedValue(config, key);
    if (val === undefined || val === null) return defaultValue;
    return String(val);
}

function stConfigSet(key, value, type = 'auto') {
    const config = loadConfig();
    
    let finalVal = value;
    if (type === 'bool' || (type === 'auto' && (value === 'true' || value === 'false' || value === true || value === false))) {
        finalVal = (String(value) === 'true');
    } else if (type === 'int' || (type === 'auto' && !isNaN(value) && value !== '')) {
        finalVal = Number(value);
    }
    
    setNestedValue(config, key, finalVal);
    return saveConfig(config);
}

const schemas = {
    network: [
        { key: 'port', type: 'int', label: '服务端口', desc: '监听的端口号 (默认 8000)' },
        { key: 'listen', type: 'bool', label: '允许外部访问', desc: '是否监听 0.0.0.0' },
        { key: 'protocol.ipv4', type: 'bool', label: 'IPv4 协议', desc: '启用 IPv4 支持' },
        { key: 'protocol.ipv6', type: 'bool', label: 'IPv6 协议', desc: '启用 IPv6 支持' },
        { key: 'whitelistMode', type: 'bool', label: '白名单模式', desc: '仅允许列表内的 IP 连接' },
        { key: 'whitelist', type: 'list', label: 'IP 白名单列表', desc: '使用逗号分隔多个 IP (如 127.0.0.1, 192.168.1.1)' },
        { key: 'enableForwardedWhitelist', type: 'bool', label: '检查代理请求头', desc: '检查 X-Forwarded-For (使用 Nginx 时开启)' },
        { key: 'whitelistDockerHosts', type: 'bool', label: '自动白名单 Docker', desc: '自动允许 Docker 宿主机访问' },
        { key: 'basicAuthMode', type: 'bool', label: '基础身份验证', desc: '启用全局 HTTP Basic Auth' },
        { key: 'enableUserAccounts', type: 'bool', label: '多用户系统', desc: '开启多账号隔离支持' },
        { key: 'enableDiscreetLogin', type: 'bool', label: '隐私登录模式', desc: '登录时不显示用户列表' },
        { key: 'ssl.enabled', type: 'bool', label: 'HTTPS (SSL)', desc: '启用 SSL 加密' },
        { key: 'enableCorsProxy', type: 'bool', label: 'CORS 代理', desc: '启用跨域资源共享代理' }
    ],
    performance: [
        { key: 'system.nodeMemory', type: 'select', label: 'Node.js 内存上限', desc: '防止大型聊天导致内存溢出 (OOM)', 
          options: ['0 (自动/默认)', '4096 (4GB)', '8192 (8GB)', '12288 (12GB)', 'custom (自定义)'] },
        { key: 'performance.lazyLoadCharacters', type: 'bool', label: '懒加载角色卡', desc: '极大提升启动速度' },
        { key: 'performance.useDiskCache', type: 'bool', label: '启用磁盘缓存', desc: 'Termux 建议关闭' },
        { key: 'thumbnails.enabled', type: 'bool', label: '生成缩略图', desc: '加快前端图片加载速度' },
        { key: 'thumbnails.format', type: 'select', label: '缩略图格式', desc: 'JPG体积小(推荐), PNG支持透明', options: ['jpg', 'png'] },
        { key: 'thumbnails.quality', type: 'int', label: 'JPG 质量 (0-100)', desc: '缩略图压缩质量 (默认 95)' },
        { key: 'extensions.enabled', type: 'bool', label: '启用扩展插件', desc: '加载 /extensions 插件' },
        { key: 'enableServerPlugins', type: 'bool', label: '启用服务端插件', desc: '加载服务端逻辑插件' }
    ],
    system: [
        { key: 'browserLaunch.enabled', type: 'bool', label: '自动打开浏览器', desc: '服务器启动时是否自动打开浏览器' },
        { key: 'requestProxy.enabled', type: 'bool', label: 'API 代理', desc: '酒馆连接外部 API 时是否使用代理' }
    ],
    debug: [
        { key: 'logging.enableAccessLog', type: 'bool', label: '记录访问日志', desc: '记录连接 IP 和 User Agent' },
        { key: 'logging.minLogLevel', type: 'select', label: '日志详细等级', desc: '控制台显示的最小日志级别', 
          options: ['0 (DEBUG) - 最详细', '1 (INFO) - 普通', '2 (WARN) - 仅警告', '3 (ERROR) - 仅错误'] }
    ],
    backups: [
        { key: 'backups.chat.enabled', type: 'bool', label: '聊天自动备份', desc: '在修改聊天记录时自动保存副本' },
        { key: 'backups.common.numberOfBackups', type: 'int', label: '单文件保留份数', desc: '每个聊天保留的历史版本数 (建议 5-10 以节省空间)' },
        { key: 'backups.chat.maxTotalBackups', type: 'int', label: '总计保留上限', desc: '所有聊天备份的总数限制 (-1 为不限制)' },
        { key: 'backups.chat.throttleInterval', type: 'int', label: '备份频率限制', desc: '两次备份间的最小间隔 (毫秒)' },
        { key: 'backups.chat.checkIntegrity', type: 'bool', label: '完整性校验', desc: '保存前验证文件是否损坏' }
    ],
    ai: [
        { key: 'mistral.enablePrefix', type: 'bool', label: 'Mistral 消息预填', desc: '允许使用最后一条消息预填回复 (需配合正则修剪)' },
        { key: 'claude.enableSystemPromptCache', type: 'bool', label: 'Claude 系统提示缓存', desc: '启用 Anthropic Prompt Caching (仅限静态提示词)' },
        { key: 'claude.cachingAtDepth', type: 'int', label: 'Claude 历史缓存深度', desc: '指定深度，-1为禁用，0通常最理想' },
        { key: 'claude.extendedTTL', type: 'bool', label: 'Claude 延长缓存TTL', desc: '生存时间延至1小时 (注意费用可能更高)' },
        { key: 'gemini.apiVersion', type: 'select', label: 'Gemini API 版本', desc: '使用的 API 终端版本', options: ['v1beta', 'v1alpha'] },
        { key: 'gemini.enableSystemPromptCache', type: 'bool', label: 'Gemini 系统提示缓存', desc: '启用缓存 (仅限通过 OpenRouter 访问)' },
        { key: 'gemini.image.personGeneration', type: 'select', label: 'Gemini 成人内容生成', desc: '人物生成限制策略', options: ['allow_adult', 'default'] },
        { key: 'openai.randomizeUserId', type: 'bool', label: 'OpenAI 随机用户ID', desc: '发送随机 ID 以增强隐私保护' },
        { key: 'openai.captionSystemPrompt', type: 'str', label: 'OpenAI 图像描述提示词', desc: '添加到所有图像描述请求开头的系统消息' }
    ]
};

function renderCategory(title, items) {
    while (true) {
        ui.header(title);
        
        const menuOpts = items.map(item => {
            let val = '';
            
            // 特殊处理内存配置读取
            if (item.key === 'system.nodeMemory') {
                const mem = getMemoryLimit();
                val = mem === 0 ? '自动/默认' : `${mem} MB`;
            } else {
                val = stConfigGet(item.key);
            }

            let status = '';
            let icon = '⚪';
            
            if (item.type === 'bool') {
                const isTrue = val === 'true';
                icon = isTrue ? '🟢' : '🔴';
                status = isTrue ? '[开启]' : '[关闭]';
            } else {
                icon = '✏️ ';
                status = `[${val}]`;
            }
            return `${icon} ${item.label} ${status}`;
        });
        
        menuOpts.push('🔙 返回上级');
        
        const choice = ui.menu('选择配置项进行修改', menuOpts);
        if (!choice || choice.includes('返回')) break;
        
        const idx = menuOpts.indexOf(choice);
        const item = items[idx];
        
        console.log(`\n设置项: ${item.key}`);
        console.log(`说明: ${item.desc}\n`);
        
        if (item.type === 'bool') {
            const cur = stConfigGet(item.key) === 'true';
            
            if (item.key === 'requestProxy.enabled' && !cur) {
                let currentUrl = stConfigGet('requestProxy.url');
                if (!currentUrl || currentUrl === 'null' || currentUrl.includes('example.com')) {
                    currentUrl = 'http://127.0.0.1:7890';
                }
                const newUrl = ui.input('请输入代理地址', currentUrl);
                if (newUrl) {
                    stConfigSet('requestProxy.url', newUrl, 'str');
                    stConfigSet(item.key, true, 'bool');
                    ui.print('success', `${env.colors.green}代理已开启并设置地址${env.colors.nc}`);
                } else {
                    ui.print('warn', '已取消开启');
                }
                ui.pause();
                continue;
            }

            if (item.key === 'basicAuthMode' && !cur) {
                const u = ui.input('设置 Basic Auth 用户名', 'user');
                const p = ui.input('设置 Basic Auth 密码', 'password', true);
                if (u && p) {
                    const config = loadConfig();
                    config.basicAuthUser = { username: u, password: p };
                    config.basicAuthMode = true;
                    saveConfig(config);
                    ui.print('success', `${env.colors.green}身份验证已开启${env.colors.nc}`);
                } else {
                    ui.print('warn', '已取消开启');
                }
                ui.pause();
                continue;
            }

            const next = !cur;
            stConfigSet(item.key, next, 'bool');
            const colorText = next ? `${env.colors.green}true${env.colors.nc}` : `${env.colors.red}false${env.colors.nc}`;
            ui.print('info', `已切换为: ${colorText}`);
            ui.pause(); 
        } else if (item.type === 'list') {
            const config = loadConfig();
            const curArr = getNestedValue(config, item.key) || [];
            const curStr = Array.isArray(curArr) ? curArr.join(', ') : String(curArr);
            const input = ui.input(`编辑列表 (用逗号分隔)`, curStr);
            if (input !== null) {
                const newArr = input.split(/[,，]/).map(s => s.trim()).filter(s => s !== '');
                setNestedValue(config, item.key, newArr);
                saveConfig(config);
                ui.print('success', `${env.colors.green}列表已更新${env.colors.nc}`);
            }
            ui.pause();
        } else if (item.type === 'select') {
            // 特殊处理内存配置写入
            if (item.key === 'system.nodeMemory') {
                const totalMem = (os.totalmem() / 1024 / 1024 / 1024).toFixed(1);
                const freeMem = (os.freemem() / 1024 / 1024 / 1024).toFixed(1);
                console.log(`${env.colors.gray}  当前设备内存: ${totalMem} GB (可用: ${freeMem} GB)${env.colors.nc}\n`);
                
                const choiceStr = ui.menu(`选择 ${item.label}`, item.options);
                if (choiceStr) {
                    let val = 0;
                    if (choiceStr.includes('custom')) {
                        const input = ui.input('请输入内存上限 (MB)', '4096');
                        if (input && !isNaN(input)) val = parseInt(input);
                    } else {
                        val = parseInt(choiceStr.split(' ')[0]);
                    }
                    
                    setMemoryLimit(val);
                    ui.print('success', `${env.colors.green}内存配置已更新，重启生效${env.colors.nc}`);
                }
                ui.pause();
                continue;
            }

            // 处理下拉选择类型
            const choiceStr = ui.menu(`选择 ${item.label}`, item.options);
            if (choiceStr) {
                const firstPart = choiceStr.split(' ')[0];
                if (!isNaN(parseInt(firstPart))) {
                    const val = parseInt(firstPart);
                    stConfigSet(item.key, val, 'int');
                } else {
                    const finalVal = choiceStr === 'default' ? '' : choiceStr;
                    stConfigSet(item.key, finalVal, 'str');
                }
                ui.print('success', `${env.colors.green}已保存: ${choiceStr}${env.colors.nc}`);
            }
            ui.pause();
        } else {
            const cur = stConfigGet(item.key);
            const input = ui.input(`请输入新的 ${item.label}`, cur);
            if (item.type === 'int' && isNaN(input)) {
                ui.print('error', '无效数字');
            } else {
                stConfigSet(item.key, input, item.type);
                ui.print('success', `${env.colors.green}已保存${env.colors.nc}`);
            }
            ui.pause();
        }
    }
}

function applyRecommended() {
    ui.print('info', '正在应用基础推荐配置...');
    stConfigSet('extensions.enabled', true, 'bool');
    stConfigSet('enableServerPlugins', true, 'bool');
    stConfigSet('performance.useDiskCache', false, 'bool');
    ui.print('success', `${env.colors.green}基础推荐配置已应用${env.colors.nc}`);
}

function applyTermuxRecommended() {
    ui.print('info', '正在应用 Termux 优化配置...');
    
    const config = loadConfig();
    
    setNestedValue(config, 'performance.useDiskCache', false);
    setNestedValue(config, 'performance.lazyLoadCharacters', true);
    setNestedValue(config, 'backups.common.numberOfBackups', 20);
    setNestedValue(config, 'backups.chat.maxTotalBackups', 500);
    setNestedValue(config, 'backups.chat.throttleInterval', 600000);
    
    saveConfig(config);
    
    ui.print('success', `${env.colors.green}Termux 优化配置已应用！${env.colors.nc}`);
    console.log(`${env.colors.gray}  - 磁盘缓存: OFF\n  - 角色懒加载: ON\n  - 备份份数: 20\n  - 备份上限: 500\n  - 备份频率: 10min${env.colors.nc}\n`);
}

function enablePublicAccess() {
    ui.header('一键开启公网访问');
    ui.print('warn', '此操作将开放 0.0.0.0 监听，允许外部设备访问。');
    ui.print('info', '为了安全，系统强制要求开启多用户模式并设置管理员密码。');
    
    if (!ui.confirm('确定要继续吗？')) return;

    console.log('\n请为管理员账号 (default-user) 设置一个强密码:');
    const pass = ui.input('输入新密码', '', true);
    
    if (!pass) {
        ui.print('error', '必须设置密码才能开启公网模式！操作已取消。');
        ui.pause();
        return;
    }

    try {
        process.chdir(ST_DIR);
        execSync(`node recover.js "default-user" "${pass}"`, { stdio: 'inherit' });
        ui.print('success', '管理员密码已设置');
    } catch (e) {
        ui.print('error', '密码设置失败，请检查酒馆是否安装完整。');
        ui.pause();
        return;
    }

    const config = loadConfig();
    setNestedValue(config, 'listen', true);
    setNestedValue(config, 'whitelistMode', false);
    setNestedValue(config, 'enableUserAccounts', true);
    setNestedValue(config, 'enableDiscreetLogin', true);
    setNestedValue(config, 'basicAuthMode', false);
    
    saveConfig(config);
    
    ui.print('success', `${env.colors.green}公网访问模式已开启！${env.colors.nc}`);
    console.log(`${env.colors.gray}  - 监听地址: 0.0.0.0\n  - 白名单: OFF\n  - 多用户: ON\n  - 隐私登录: ON${env.colors.nc}\n`);
    ui.pause();
}

function resetConfig() {
    ui.header('恢复默认配置');
    ui.print('warn', '警告：此操作将删除 config.yaml 文件并重置所有设置！');
    
    if (ui.confirm('确定要恢复默认配置吗？')) {
        try {
            if (fs.existsSync(CONFIG_FILE)) {
                fs.unlinkSync(CONFIG_FILE);
                ui.print('success', `${env.colors.green}配置文件已删除。${env.colors.nc}`);
                ui.print('info', '下次重启酒馆时，系统将自动生成全新的默认配置。');
            } else {
                ui.print('error', '未找到配置文件。');
            }
        } catch (e) {
            ui.print('error', `重置失败: ${e.message}`);
        }
        ui.pause();
    }
}

function resetPassword() {
    ui.header('重置密码');
    const user = ui.input('请输入用户名', 'default-user');
    const pass = ui.input('请输入新密码', '', true);
    
    if (user && pass) {
        try {
            process.chdir(ST_DIR);
            execSync(`node recover.js "${user}" "${pass}"`, { stdio: 'inherit' });
            ui.print('success', '密码已重置');
        } catch (e) {
            ui.print('error', '重置失败，请确认用户名');
        }
    }
    ui.pause();
}

function mainMenu() {
    if (!fs.existsSync(CONFIG_FILE)) {
        ui.print('error', '配置文件不存在，请先安装酒馆。');
        ui.pause();
        return;
    }

    while (true) {
        ui.header('SillyTavern 配置管理');
        
        const opts = [
            '🚀 一键应用Termux推荐配置',
            '🌍 一键开启公网访问',
            '🌐 网络与安全设置',
            '⚡ 性能与插件优化',
            '🖥️  界面与系统设置',
            '🤖 AI模型与API',
            '💾 自动备份设置',
            '🛠️  调试与日志',
            '🔐 重置管理员密码',
            '💥 恢复默认配置',
            '🔙 返回主程序'
        ];
        
        const choice = ui.menu('请选择配置类别', opts);
        if (!choice || choice.includes('返回')) break;
        
        if (choice.includes('Termux')) {
            if (ui.confirm('确定要应用 Termux 优化配置吗？')) {
                applyTermuxRecommended();
                ui.pause();
            }
        }
        else if (choice.includes('公网')) enablePublicAccess();
        else if (choice.includes('网络')) renderCategory('网络与安全', schemas.network);
        else if (choice.includes('性能')) renderCategory('性能优化', schemas.performance);
        else if (choice.includes('界面')) renderCategory('界面与系统', schemas.system);
        else if (choice.includes('AI')) renderCategory('AI 模型与 API', schemas.ai);
        else if (choice.includes('备份')) renderCategory('自动备份设置', schemas.backups);
        else if (choice.includes('调试')) renderCategory('调试与日志', schemas.debug);
        else if (choice.includes('密码')) resetPassword();
        else if (choice.includes('恢复默认')) resetConfig();
    }
}

if (process.argv.includes('--recommended')) {
    applyRecommended();
} else if (process.argv.includes('--termux')) {
    applyTermuxRecommended();
} else {
    mainMenu();
}