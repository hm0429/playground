// 音声録音設定
module.exports = {
  // 録音間隔（秒）
  RECORDING_INTERVAL_SECONDS: 10,
  
  // 音声ファイル保存ディレクトリ
  OUTPUT_DIRECTORY: './recorded_audio',
  
  // 音声フォーマット設定
  AUDIO_CONFIG: {
    sampleRate: 16000,
    channels: 1,
    audioType: 'wav', // 中間フォーマット
    encoding: 'signed-integer',
    endian: 'little',
    bitwidth: 16
  },
  
  // MP3エンコード設定
  MP3_CONFIG: {
    codec: 'libmp3lame',
    bitrate: '128k'
  }
};