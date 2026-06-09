export type Lang = "ko" | "en" | "ja";

export interface Translations {
  appName: string;
  // menus
  fileMenu: string;
  editMenu: string;
  subtitleMenu: string;
  playbackMenu: string;
  viewMenu: string;
  resetLayout: string;
  panelVideo: string;
  panelWaveform: string;
  panelSubtitles: string;
  noMedia: string;
  pluginManager: string;
  pluginOpen: string;
  pluginAdd: string;
  pluginAddNew: string;
  pluginName: string;
  plugins: string;
  spectrogram: string;
  editTags: string;
  inlineTagEditor: string;
  tagColor: string;
  tagStructured: string;
  tagRaw: string;
  addTag: string;
  noTags: string;
  embeddedAssets: string;
  embeddedFonts: string;
  embeddedGraphics: string;
  embeddedEmpty: string;
  translation: string;
  translationPlaceholder: string;
  showTranslation: string;
  preview: string;
  noActiveCue: string;
  playPause: string;
  skipBack5: string;
  skipBack1: string;
  skipFwd1: string;
  skipFwd5: string;
  // toolbar
  newFile: string;
  open: string;
  openMedia: string;
  closeMedia: string;
  addCueAtPlayhead: string;
  cueHere: string;
  save: string;
  exportAs: string;
  undo: string;
  redo: string;
  language: string;
  settings: string;
  help: string;
  unsaved: string;
  untitled: string;
  // cue list
  cueNumber: string;
  start: string;
  end: string;
  duration: string;
  text: string;
  addCue: string;
  deleteCue: string;
  splitCue: string;
  mergeCues: string;
  shiftTime: string;
  noCues: string;
  emptyHint: string;
  // quality
  overlap: string;
  cpsHigh: string;
  tooShort: string;
  tooLong: string;
  // modals
  confirm: string;
  cancel: string;
  close: string;
  newFileConfirm: string;
  chooseExportFormat: string;
  rawEdit: string;
  rawEditHint: string;
  apply: string;
  shiftPrompt: string;
  shiftAll: string;
  shiftSelected: string;
  // settings
  uiScale: string;
  autoCheckUpdate: string;
  updateAvailable: string;
  // shortcuts help
  shortcuts: string;
  scUndo: string;
  scRedo: string;
  scSave: string;
  scOpen: string;
  scNew: string;
  // styles
  styles: string;
  styleManager: string;
  addStyle: string;
  deleteStyle: string;
  styleName: string;
  font: string;
  fontSize: string;
  primaryColour: string;
  outlineColour: string;
  backColour: string;
  bold: string;
  italic: string;
  outlineWidth: string;
  shadowDepth: string;
  alignment: string;
  noStyles: string;
  cueStyle: string;
  defaultStyle: string;
  // lossy export warning
  exportLossTitle: string;
  exportLossDesc: string;
  exportLossKeepHint: string;
  continueExport: string;
  lossPosition: string;
  lossKaraoke: string;
  lossAnimation: string;
  lossTransform: string;
  lossBorderShadow: string;
  lossDrawing: string;
  lossClip: string;
  lossColor: string;
  lossOther: string;
}

const ko: Translations = {
  appName: "Glyphline",
  fileMenu: "파일",
  editMenu: "편집",
  subtitleMenu: "자막",
  playbackMenu: "재생",
  viewMenu: "보기",
  resetLayout: "레이아웃 초기화",
  panelVideo: "영상",
  panelWaveform: "파형",
  panelSubtitles: "자막",
  noMedia: "미디어를 열어주세요 (파일 ▸ 미디어 열기)",
  pluginManager: "플러그인 관리",
  pluginOpen: "열기",
  pluginAdd: "추가",
  pluginAddNew: "새 플러그인 추가 (URL)",
  pluginName: "이름",
  plugins: "플러그인",
  spectrogram: "스펙트로그램",
  editTags: "인라인 태그 편집…",
  inlineTagEditor: "인라인 태그 편집 (ASS)",
  tagColor: "색상",
  tagStructured: "구조",
  tagRaw: "고급(raw)",
  addTag: "태그 추가",
  noTags: "태그 없음",
  embeddedAssets: "내장 폰트/그래픽",
  embeddedFonts: "폰트",
  embeddedGraphics: "그래픽",
  embeddedEmpty: "내장된 파일이 없습니다.",
  translation: "번역",
  translationPlaceholder: "번역 입력…",
  showTranslation: "번역 열 표시",
  preview: "미리보기",
  noActiveCue: "선택된 자막이 없습니다. 먼저 자막을 선택하세요.",
  playPause: "재생 / 일시정지",
  skipBack5: "5초 뒤로",
  skipBack1: "1초 뒤로",
  skipFwd1: "1초 앞으로",
  skipFwd5: "5초 앞으로",
  newFile: "새 파일",
  open: "열기",
  openMedia: "미디어 열기…",
  closeMedia: "미디어 닫기",
  addCueAtPlayhead: "재생 위치에 자막 추가",
  cueHere: "여기에 자막",
  save: "저장",
  exportAs: "내보내기",
  undo: "실행 취소",
  redo: "다시 실행",
  language: "언어",
  settings: "설정",
  help: "도움말",
  unsaved: "저장 안 됨",
  untitled: "제목 없음",
  cueNumber: "#",
  start: "시작",
  end: "종료",
  duration: "길이",
  text: "텍스트",
  addCue: "자막 추가",
  deleteCue: "삭제",
  splitCue: "분할",
  mergeCues: "병합",
  shiftTime: "시간 이동",
  noCues: "자막이 없습니다",
  emptyHint: "파일을 열거나 자막을 추가하세요.",
  overlap: "이전 자막과 겹침",
  cpsHigh: "CPS 초과 (너무 빠름)",
  tooShort: "표시 시간이 너무 짧음",
  tooLong: "표시 시간이 너무 김",
  confirm: "확인",
  cancel: "취소",
  close: "닫기",
  newFileConfirm: "현재 작업을 버리고 새 파일을 만들까요? 저장되지 않은 변경사항은 사라집니다.",
  chooseExportFormat: "내보낼 포맷을 선택하세요",
  rawEdit: "원본 텍스트 편집",
  rawEditHint: "현재 포맷으로 직렬화된 내용입니다. 수정 후 적용하면 다시 파싱됩니다.",
  apply: "적용",
  shiftPrompt: "이동할 시간(초). 음수는 앞으로 당깁니다.",
  shiftAll: "전체",
  shiftSelected: "선택 항목",
  uiScale: "UI 배율",
  autoCheckUpdate: "시작 시 업데이트 확인",
  updateAvailable: "새 버전이 있습니다",
  shortcuts: "단축키",
  scUndo: "실행 취소",
  scRedo: "다시 실행",
  scSave: "저장 (.glyph)",
  scOpen: "열기",
  scNew: "새 파일",
  styles: "스타일",
  styleManager: "스타일 매니저",
  addStyle: "스타일 추가",
  deleteStyle: "삭제",
  styleName: "이름",
  font: "폰트",
  fontSize: "크기",
  primaryColour: "기본 색상",
  outlineColour: "외곽선 색상",
  backColour: "배경/그림자 색상",
  bold: "굵게",
  italic: "기울임",
  outlineWidth: "외곽선 두께",
  shadowDepth: "그림자",
  alignment: "정렬",
  noStyles: "스타일이 없습니다. (ASS 전용)",
  cueStyle: "스타일",
  defaultStyle: "기본",
  exportLossTitle: "일부 서식이 제거됩니다",
  exportLossDesc: "이 포맷이 표현할 수 없는 다음 ASS 기능은 내보내기에서 제거됩니다:",
  exportLossKeepHint: "원본을 그대로 보존하려면 .glyph 또는 .ass로 저장하세요.",
  continueExport: "계속 내보내기",
  lossPosition: "위치/정렬 (\\pos, \\an)",
  lossKaraoke: "가라오케 타이밍 (\\k)",
  lossAnimation: "애니메이션/페이드 (\\t, \\fad)",
  lossTransform: "회전/크기 변형 (\\frz, \\fscx)",
  lossBorderShadow: "외곽선/그림자/블러",
  lossDrawing: "벡터 그리기 (\\p)",
  lossClip: "클립 마스크 (\\clip)",
  lossColor: "보조 색상/투명도",
  lossOther: "기타 태그",
};

const en: Translations = {
  appName: "Glyphline",
  fileMenu: "File",
  editMenu: "Edit",
  subtitleMenu: "Subtitle",
  playbackMenu: "Playback",
  viewMenu: "View",
  resetLayout: "Reset Layout",
  panelVideo: "Video",
  panelWaveform: "Waveform",
  panelSubtitles: "Subtitles",
  noMedia: "Open media first (File ▸ Open Media)",
  pluginManager: "Plugin Manager",
  pluginOpen: "Open",
  pluginAdd: "Add",
  pluginAddNew: "Add new plugin (URL)",
  pluginName: "Name",
  plugins: "Plugins",
  spectrogram: "Spectrogram",
  editTags: "Edit Inline Tags…",
  inlineTagEditor: "Inline Tag Editor (ASS)",
  tagColor: "Color",
  tagStructured: "Structured",
  tagRaw: "Raw",
  addTag: "Add tag",
  noTags: "No tags",
  embeddedAssets: "Embedded Fonts/Graphics",
  embeddedFonts: "Fonts",
  embeddedGraphics: "Graphics",
  embeddedEmpty: "No embedded files.",
  translation: "Translation",
  translationPlaceholder: "Enter translation…",
  showTranslation: "Show Translation Column",
  preview: "Preview",
  noActiveCue: "No cue selected. Select a cue first.",
  playPause: "Play / Pause",
  skipBack5: "Back 5s",
  skipBack1: "Back 1s",
  skipFwd1: "Forward 1s",
  skipFwd5: "Forward 5s",
  newFile: "New",
  open: "Open",
  openMedia: "Open Media…",
  closeMedia: "Close Media",
  addCueAtPlayhead: "Add cue at playhead",
  cueHere: "Cue here",
  save: "Save",
  exportAs: "Export",
  undo: "Undo",
  redo: "Redo",
  language: "Language",
  settings: "Settings",
  help: "Help",
  unsaved: "Unsaved",
  untitled: "Untitled",
  cueNumber: "#",
  start: "Start",
  end: "End",
  duration: "Dur",
  text: "Text",
  addCue: "Add cue",
  deleteCue: "Delete",
  splitCue: "Split",
  mergeCues: "Merge",
  shiftTime: "Shift time",
  noCues: "No cues",
  emptyHint: "Open a file or add a cue to begin.",
  overlap: "Overlaps previous cue",
  cpsHigh: "CPS too high (too fast)",
  tooShort: "Display time too short",
  tooLong: "Display time too long",
  confirm: "OK",
  cancel: "Cancel",
  close: "Close",
  newFileConfirm: "Discard the current work and start a new file? Unsaved changes will be lost.",
  chooseExportFormat: "Choose a format to export",
  rawEdit: "Edit raw text",
  rawEditHint: "Serialized in the current format. Editing and applying re-parses it.",
  apply: "Apply",
  shiftPrompt: "Seconds to shift. Negative moves earlier.",
  shiftAll: "All",
  shiftSelected: "Selected",
  uiScale: "UI scale",
  autoCheckUpdate: "Check for updates on launch",
  updateAvailable: "A new version is available",
  shortcuts: "Shortcuts",
  scUndo: "Undo",
  scRedo: "Redo",
  scSave: "Save (.glyph)",
  scOpen: "Open",
  scNew: "New file",
  styles: "Styles",
  styleManager: "Style Manager",
  addStyle: "Add style",
  deleteStyle: "Delete",
  styleName: "Name",
  font: "Font",
  fontSize: "Size",
  primaryColour: "Primary colour",
  outlineColour: "Outline colour",
  backColour: "Back/shadow colour",
  bold: "Bold",
  italic: "Italic",
  outlineWidth: "Outline width",
  shadowDepth: "Shadow",
  alignment: "Alignment",
  noStyles: "No styles. (ASS only)",
  cueStyle: "Style",
  defaultStyle: "Default",
  exportLossTitle: "Some formatting will be removed",
  exportLossDesc: "This format can't represent the following ASS features, which will be dropped on export:",
  exportLossKeepHint: "Save as .glyph or .ass to keep the original intact.",
  continueExport: "Export anyway",
  lossPosition: "Position/alignment (\\pos, \\an)",
  lossKaraoke: "Karaoke timing (\\k)",
  lossAnimation: "Animation/fade (\\t, \\fad)",
  lossTransform: "Rotation/scale (\\frz, \\fscx)",
  lossBorderShadow: "Outline/shadow/blur",
  lossDrawing: "Vector drawing (\\p)",
  lossClip: "Clip mask (\\clip)",
  lossColor: "Secondary colours/alpha",
  lossOther: "Other tags",
};

const ja: Translations = {
  appName: "Glyphline",
  fileMenu: "ファイル",
  editMenu: "編集",
  subtitleMenu: "字幕",
  playbackMenu: "再生",
  viewMenu: "表示",
  resetLayout: "レイアウトをリセット",
  panelVideo: "映像",
  panelWaveform: "波形",
  panelSubtitles: "字幕",
  noMedia: "メディアを開いてください（ファイル ▸ メディアを開く）",
  pluginManager: "プラグイン管理",
  pluginOpen: "開く",
  pluginAdd: "追加",
  pluginAddNew: "新しいプラグインを追加 (URL)",
  pluginName: "名前",
  plugins: "プラグイン",
  spectrogram: "スペクトログラム",
  editTags: "インラインタグ編集…",
  inlineTagEditor: "インラインタグ編集 (ASS)",
  tagColor: "色",
  tagStructured: "構造",
  tagRaw: "Raw",
  addTag: "タグ追加",
  noTags: "タグなし",
  embeddedAssets: "埋め込みフォント/グラフィック",
  embeddedFonts: "フォント",
  embeddedGraphics: "グラフィック",
  embeddedEmpty: "埋め込みファイルがありません。",
  translation: "翻訳",
  translationPlaceholder: "翻訳を入力…",
  showTranslation: "翻訳列を表示",
  preview: "プレビュー",
  noActiveCue: "字幕が選択されていません。まず字幕を選択してください。",
  playPause: "再生 / 一時停止",
  skipBack5: "5秒戻る",
  skipBack1: "1秒戻る",
  skipFwd1: "1秒進む",
  skipFwd5: "5秒進む",
  newFile: "新規",
  open: "開く",
  openMedia: "メディアを開く…",
  closeMedia: "メディアを閉じる",
  addCueAtPlayhead: "再生位置に字幕を追加",
  cueHere: "ここに字幕",
  save: "保存",
  exportAs: "書き出し",
  undo: "元に戻す",
  redo: "やり直し",
  language: "言語",
  settings: "設定",
  help: "ヘルプ",
  unsaved: "未保存",
  untitled: "無題",
  cueNumber: "#",
  start: "開始",
  end: "終了",
  duration: "長さ",
  text: "テキスト",
  addCue: "字幕を追加",
  deleteCue: "削除",
  splitCue: "分割",
  mergeCues: "結合",
  shiftTime: "時間シフト",
  noCues: "字幕がありません",
  emptyHint: "ファイルを開くか、字幕を追加してください。",
  overlap: "前の字幕と重複",
  cpsHigh: "CPS 超過（速すぎ）",
  tooShort: "表示時間が短すぎ",
  tooLong: "表示時間が長すぎ",
  confirm: "OK",
  cancel: "キャンセル",
  close: "閉じる",
  newFileConfirm: "現在の作業を破棄して新規ファイルを作成しますか？未保存の変更は失われます。",
  chooseExportFormat: "書き出す形式を選択",
  rawEdit: "ソーステキスト編集",
  rawEditHint: "現在の形式でシリアライズされた内容です。編集して適用すると再パースされます。",
  apply: "適用",
  shiftPrompt: "シフトする秒数。負の値で早める。",
  shiftAll: "全体",
  shiftSelected: "選択",
  uiScale: "UI 倍率",
  autoCheckUpdate: "起動時に更新を確認",
  updateAvailable: "新しいバージョンがあります",
  shortcuts: "ショートカット",
  scUndo: "元に戻す",
  scRedo: "やり直し",
  scSave: "保存 (.glyph)",
  scOpen: "開く",
  scNew: "新規ファイル",
  styles: "スタイル",
  styleManager: "スタイルマネージャ",
  addStyle: "スタイル追加",
  deleteStyle: "削除",
  styleName: "名前",
  font: "フォント",
  fontSize: "サイズ",
  primaryColour: "基本色",
  outlineColour: "縁取り色",
  backColour: "背景/影色",
  bold: "太字",
  italic: "斜体",
  outlineWidth: "縁取り幅",
  shadowDepth: "影",
  alignment: "配置",
  noStyles: "スタイルがありません。(ASS 専用)",
  cueStyle: "スタイル",
  defaultStyle: "デフォルト",
  exportLossTitle: "一部の書式が削除されます",
  exportLossDesc: "この形式では表現できない次の ASS 機能は、書き出し時に削除されます:",
  exportLossKeepHint: "元のまま保持するには .glyph または .ass で保存してください。",
  continueExport: "このまま書き出す",
  lossPosition: "位置/配置 (\\pos, \\an)",
  lossKaraoke: "カラオケタイミング (\\k)",
  lossAnimation: "アニメーション/フェード (\\t, \\fad)",
  lossTransform: "回転/拡大縮小 (\\frz, \\fscx)",
  lossBorderShadow: "縁取り/影/ぼかし",
  lossDrawing: "ベクター描画 (\\p)",
  lossClip: "クリップマスク (\\clip)",
  lossColor: "補助色/不透明度",
  lossOther: "その他のタグ",
};

export const translations: Record<Lang, Translations> = { ko, en, ja };
