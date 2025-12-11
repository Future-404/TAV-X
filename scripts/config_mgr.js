/**
 * TAV-X Configuration Manager (The Scalpel) v2.4
 * Update: Batch Processing & Fsync (Fix I/O Hammering)
 */

const fs = require('fs');
const path = require('path');

const INSTALL_DIR = process.env.INSTALL_DIR || path.join(process.env.HOME, 'SillyTavern');
const CONFIG_PATH = path.join(INSTALL_DIR, 'config.yaml');

if (!fs.existsSync(CONFIG_PATH)) {
    console.error(`❌ Config file not found: ${CONFIG_PATH}`);
    process.exit(1);
}

const args = process.argv.slice(2);
const action = args[0]; 
const keyOrJson = args[1]; 
const valParam = args[2]; 

if (!action || !keyOrJson) {
    console.error("Usage: node config_mgr.js [get|set|set-batch] [key|json] [value]");
    process.exit(1);
}

function parseLineValue(line) {
    const match = line.match(/:\s*(.*)/);
    if (!match) return { val: '', comment: '' };
    const raw = match[1];
    const commentIdx = raw.indexOf('#');
    if (commentIdx !== -1) {
        return {
            val: raw.substring(0, commentIdx).trim(),
            comment: raw.substring(commentIdx) 
        };
    }
    return { val: raw.trim(), comment: '' };
}

function getIndent(line) {
    const match = line.match(/^(\s*)/);
    return match ? match[1].length : 0;
}

function getKey(line) {
    const match = line.match(/^\s*([\w\-"']+):/);
    if (!match) return null;
    return match[1].replace(/['"]/g, '');
}

function applyChange(lines, keyPath, newValue) {
    const keys = keyPath.split('.');
    let currentDepth = 0;
    let pathFound = false;
    let isChanged = false;

    const newLines = lines.map(line => {
        if (line.trim().startsWith('#') || line.trim() === '') return line;
        if (pathFound && currentDepth >= keys.length) return line;

        const key = getKey(line);
        
        if (key === keys[currentDepth]) {
            if (currentDepth === 0 && getIndent(line) > 0) return line;

            if (currentDepth === keys.length - 1) {
                pathFound = true;
                const { val: currentValRaw } = parseLineValue(line);
                const currentValClean = currentValRaw.replace(/^['"]|['"]$/g, '');
                const newValClean = String(newValue).replace(/^['"]|['"]$/g, '');

                if (currentValClean == newValClean) {
                    return line;
                }

                if (currentValRaw.trim().endsWith('>') || currentValRaw.trim().endsWith('|')) {
                    console.warn(`⚠️ Skipped complex value for ${keyPath}`);
                    return line;
                }

                isChanged = true;
                const indentStr = line.match(/^(\s*)/)[1];
                const { comment } = parseLineValue(line);
                
                let finalLine = `${indentStr}${key}: ${newValue}`;
                if (comment) finalLine += ` ${comment}`;
                
                return finalLine;
            } else {
                currentDepth++;
            }
        }
        return line;
    });

    return { lines: newLines, changed: isChanged };
}

let content;
try {
    content = fs.readFileSync(CONFIG_PATH, 'utf8');
} catch (err) {
    console.error(`❌ Read error: ${err.message}`);
    process.exit(1);
}
let lines = content.split('\n');

if (action === 'get') {
    const keys = keyOrJson.split('.');
    let currentDepth = 0;
    for (const line of lines) {
        if (line.trim().startsWith('#') || line.trim() === '') continue;
        const key = getKey(line);
        if (key === keys[currentDepth]) {
            if (currentDepth === 0 && getIndent(line) > 0) continue;
            if (currentDepth === keys.length - 1) {
                const { val } = parseLineValue(line);
                console.log(val.replace(/^['"]|['"]$/g, ''));
                process.exit(0);
            } else currentDepth++;
        }
    }
    process.exit(1);
} 

else if (action === 'set') {
    const { lines: newLines, changed } = applyChange(lines, keyOrJson, valParam);
    if (changed) writeAtomic(newLines);
    process.exit(0);
}

else if (action === 'set-batch') {
    let updates;
    try {
        updates = JSON.parse(keyOrJson);
    } catch (e) {
        console.error("❌ Invalid JSON for batch update");
        process.exit(1);
    }

    let anyChanged = false;
    for (const [k, v] of Object.entries(updates)) {
        const result = applyChange(lines, k, v);
        lines = result.lines;
        if (result.changed) anyChanged = true;
    }

    if (anyChanged) {
        writeAtomic(lines);
    } else {
    }
    process.exit(0);
}

function writeAtomic(linesData) {
    const tempPath = CONFIG_PATH + '.tmp';
    let fd;
    try {
        fd = fs.openSync(tempPath, 'w');
        fs.writeSync(fd, linesData.join('\n'), 'utf8');
        fs.fsyncSync(fd);
        fs.closeSync(fd);
        fs.renameSync(tempPath, CONFIG_PATH);
    } catch (err) {
        console.error(`❌ Write Failed: ${err.message}`);
        if (fd) try { fs.closeSync(fd); } catch(e){}
        try { fs.unlinkSync(tempPath); } catch (e) {} 
        process.exit(1);
    }
}