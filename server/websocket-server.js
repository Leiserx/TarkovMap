const WebSocket = require('ws');
const http = require('http');

// 默认端口
const PORT = process.env.PORT || 8080;


// 创建 HTTP 服务器
const server = http.createServer((req, res) => {
  // 设置CORS头
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  // 其他请求返回404
  res.writeHead(404);
  res.end('Not Found');
});

// 创建 WebSocket 服务器
const wss = new WebSocket.Server({ server });

// 存储所有连接的客户端
const clients = new Map();

// 启动服务器
server.listen(PORT, () => {
  console.log(`HTTP/WebSocket 服务器启动在端口 ${PORT}`);
  console.log('服务器就绪，等待客户端连接...\n');
});

// 广播消息给除发送者外的所有客户端
function broadcast(message, excludeClient) {
  const data = JSON.stringify(message);
  
  clients.forEach((client, ws) => {
    if (ws !== excludeClient && ws.readyState === WebSocket.OPEN) {
      ws.send(data);
    }
  });
}

function sanitizePositionMessage(msg) {
  const user = typeof msg.user === 'string' ? msg.user.trim() : ''
  const mapRaw = typeof msg.map === 'string' ? msg.map.trim() : ''
  const map = mapRaw.toLowerCase()
  let xyz = Array.isArray(msg.xyz) ? msg.xyz.slice(0, 3) : []
  if (xyz.length === 2) {
    xyz = [Number(xyz[0]) || 0, 0, Number(xyz[1]) || 0]
  } else {
    xyz = [Number(xyz[0]) || 0, Number(xyz[1]) || 0, Number(xyz[2]) || 0]
  }
  const rotation = typeof msg.rotation === 'number' ? msg.rotation : Number(msg.rotation) || 0
  return {
    type: 'position',
    user,
    map,
    xyz,
    rotation
  }
}

const isDevEnv = process.env.NODE_ENV !== 'production'
const echoSenderFlag = (process.env.ECHO_SENDER || '').toLowerCase()
const echoSender = echoSenderFlag ? echoSenderFlag === 'true' : isDevEnv

// 处理客户端连接
wss.on('connection', (ws, req) => {
  const clientIp = req.socket.remoteAddress;
  console.log(`新客户端连接: ${clientIp}`);
  
  // 初始化客户端信息
  clients.set(ws, {
    ip: clientIp,
    connectedAt: new Date(),
    lastHeartbeat: Date.now(),
    user: null // 将在收到消息时设置
  });

  // 处理客户端消息
  ws.on('message', (data) => {
    try {
      const message = JSON.parse(data.toString());
      
      // 更新客户端用户信息
      const clientInfo = clients.get(ws);
      if (clientInfo && message.user && !clientInfo.user) {
        clientInfo.user = message.user;
        console.log(`客户端 ${clientIp} 标识为用户: ${message.user}`);
      }
      
      // 处理连接请求
      if (message.status === 'connect') {
        console.log(`客户端 ${clientIp} 请求连接`);
        ws.send(JSON.stringify({ status: 'success' }));
        return;
      }
      
      // 处理心跳
      if (message.type === 'heartbeat') {
        if (clientInfo) {
          clientInfo.lastHeartbeat = Date.now();
        }
        ws.send(JSON.stringify({ type: 'heartbeat', status: 'ok' }));
        return;
      }
      
      // 处理位置更新
      if (message.user && message.map && message.xyz) {
        const sanitized = sanitizePositionMessage(message)
        console.log(`收到位置更新 - 用户: ${sanitized.user}, 地图: ${sanitized.map}, 坐标: [${sanitized.xyz.join(', ')}], 旋转: ${sanitized.rotation}`);
        const exclude = echoSender ? null : ws
        broadcast(sanitized, exclude);
        if (echoSender && ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify(sanitized))
        }
      }
    } catch (error) {
      console.error('解析消息错误:', error);
    }
  });

  // 处理连接关闭
  ws.on('close', () => {
    console.log(`客户端断开连接: ${clientIp}`);
    clients.delete(ws);
  });

  // 处理错误
  ws.on('error', (error) => {
    console.error(`客户端错误 ${clientIp}:`, error);
  });
});

// 心跳检测 - 每30秒检查一次
setInterval(() => {
  const now = Date.now();
  const timeout = 30000; // 30秒超时
  
  clients.forEach((clientInfo, ws) => {
    if (now - clientInfo.lastHeartbeat > timeout) {
      console.log(`客户端 ${clientInfo.ip} 心跳超时，断开连接`);
      ws.terminate();
      clients.delete(ws);
    }
  });
}, 30000);

// 优雅关闭
process.on('SIGTERM', () => {
  console.log('收到 SIGTERM 信号，正在关闭服务器...');
  wss.close(() => {
    console.log('WebSocket 服务器已关闭');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  console.log('收到 SIGINT 信号，正在关闭服务器...');
  wss.close(() => {
    console.log('WebSocket 服务器已关闭');
    process.exit(0);
  });
});

