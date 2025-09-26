const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const record = require('node-record-lpcm16');
const ffmpeg = require('fluent-ffmpeg');
const ffmpegPath = require('ffmpeg-static');
const config = require('./config');

// ffmpegのパスを設定
ffmpeg.setFfmpegPath(ffmpegPath);

// 録音中フラグ
let isRecording = false;
let currentRecording = null;
let currentStream = null;
let currentFilePath = null;

// 出力ディレクトリの作成
function ensureOutputDirectory() {
  const outputDir = path.resolve(config.OUTPUT_DIRECTORY);
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
    console.log(`Created output directory: ${outputDir}`);
  }
  return outputDir;
}

// タイムスタンプを生成（yyyyMMddHHmmss形式）
function generateTimestamp() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  const hour = String(now.getHours()).padStart(2, '0');
  const minute = String(now.getMinutes()).padStart(2, '0');
  const second = String(now.getSeconds()).padStart(2, '0');
  
  return `${year}${month}${day}${hour}${minute}${second}`;
}

// WAVからMP3に変換
function convertToMp3(wavPath, mp3Path) {
  return new Promise((resolve, reject) => {
    // ファイルが存在するか確認
    if (!fs.existsSync(wavPath)) {
      reject(new Error(`WAV file not found: ${wavPath}`));
      return;
    }
    
    ffmpeg(wavPath)
      .audioCodec(config.MP3_CONFIG.codec)
      .audioBitrate(config.MP3_CONFIG.bitrate)
      .on('end', () => {
        console.log(`✓ Converted to MP3: ${path.basename(mp3Path)}`);
        // 一時的なWAVファイルを削除
        try {
          fs.unlinkSync(wavPath);
        } catch (err) {
          console.error('Failed to delete temporary WAV file:', err.message);
        }
        resolve();
      })
      .on('error', (err) => {
        console.error('Error converting to MP3:', err);
        reject(err);
      })
      .save(mp3Path);
  });
}

// 録音を保存してMP3に変換
async function saveCurrentRecording() {
  if (!currentRecording || !currentStream || !currentFilePath) {
    return;
  }
  
  const wavPath = currentFilePath;
  const mp3Path = wavPath.replace('_temp.wav', '.mp3');
  
  // ストリームを閉じる
  currentStream.end();
  
  // 録音を停止
  currentRecording.stop();
  currentRecording = null;
  currentStream = null;
  currentFilePath = null;
  
  // WAVファイルが完全に書き込まれるのを待つ
  await new Promise(resolve => setTimeout(resolve, 1000));
  
  // MP3に変換
  try {
    await convertToMp3(wavPath, mp3Path);
  } catch (error) {
    console.error('Failed to convert recording:', error.message);
  }
}

// 新しい録音を開始
async function startNewRecording() {
  // 既存の録音がある場合は保存
  if (currentRecording) {
    await saveCurrentRecording();
  }
  
  const outputDir = ensureOutputDirectory();
  const timestamp = generateTimestamp();
  const wavPath = path.join(outputDir, `${timestamp}_temp.wav`);
  
  currentFilePath = wavPath;
  currentStream = fs.createWriteStream(wavPath, { encoding: 'binary' });
  
  currentRecording = record.record({
    sampleRate: config.AUDIO_CONFIG.sampleRate,
    threshold: 0,
    verbose: false,
    recordProgram: 'rec', // MacOS用（sox）
    silence: '0.0',
  });
  
  currentRecording.stream()
    .on('error', (err) => {
      console.error('Recording stream error:', err);
    })
    .pipe(currentStream);
    
  console.log(`▶ Started recording: ${timestamp}`);
}

// メイン録音処理
async function startRecording() {
  console.log('===========================================');
  console.log('🎙  Audio Recorder Started');
  console.log(`📊 Recording interval: ${config.RECORDING_INTERVAL_SECONDS} seconds`);
  console.log(`📁 Output directory: ${path.resolve(config.OUTPUT_DIRECTORY)}`);
  console.log('⏹  Press Ctrl+C to stop recording');
  console.log('===========================================\n');
  
  isRecording = true;
  
  // 最初の録音を開始
  await startNewRecording();
  
  // 定期的に新しい録音を開始（古い録音は自動的に保存される）
  const intervalMs = config.RECORDING_INTERVAL_SECONDS * 1000;
  const saveInterval = setInterval(async () => {
    if (isRecording) {
      await startNewRecording();
    } else {
      clearInterval(saveInterval);
    }
  }, intervalMs);
}

// グレースフルシャットダウン
process.on('SIGINT', async () => {
  console.log('\n\n⏹  Stopping recorder...');
  isRecording = false;
  
  // 最後の録音を保存
  if (currentRecording) {
    await saveCurrentRecording();
    console.log('✓ Final recording saved.');
  }
  
  // 少し待ってからプロセスを終了
  setTimeout(() => {
    console.log('👋 Recorder stopped.');
    process.exit(0);
  }, 2000);
});

// SIGTERMも同様に処理
process.on('SIGTERM', async () => {
  console.log('\nReceived SIGTERM, stopping recorder...');
  isRecording = false;
  
  // 最後の録音を保存
  if (currentRecording) {
    await saveCurrentRecording();
  }
  
  setTimeout(() => {
    process.exit(0);
  }, 2000);
});

// プログラムの開始
if (require.main === module) {
  // soxがインストールされているか確認
  const { execSync } = require('child_process');
  try {
    execSync('which sox', { stdio: 'ignore' });
  } catch (error) {
    console.error('Error: sox is not installed.');
    console.error('Please install sox with: brew install sox');
    process.exit(1);
  }
  
  // 録音開始
  startRecording();
}

module.exports = {
  startRecording,
  generateTimestamp,
  ensureOutputDirectory
};