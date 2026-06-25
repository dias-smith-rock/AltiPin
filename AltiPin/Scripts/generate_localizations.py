#!/usr/bin/env python3
"""Generate Localizable.xcstrings from English keys and translations."""

import json
from pathlib import Path

from extra_translations import EXTRA_ZH

LOCALES = ["en", "zh-Hans", "zh-Hant", "ja", "es", "pt-BR", "ar", "hi", "fr"]

# English key -> { locale: translation }
TRANSLATIONS: dict[str, dict[str, str]] = {
    "Settings": {"zh-Hans": "设置", "zh-Hant": "設定", "ja": "設定", "es": "Ajustes", "pt-BR": "Ajustes", "ar": "الإعدادات", "hi": "सेटिंग्स", "fr": "Réglages"},
    "Close": {"zh-Hans": "关闭", "zh-Hant": "關閉", "ja": "閉じる", "es": "Cerrar", "pt-BR": "Fechar", "ar": "إغلاق", "hi": "बंद करें", "fr": "Fermer"},
    "Done": {"zh-Hans": "完成", "zh-Hant": "完成", "ja": "完了", "es": "Listo", "pt-BR": "Concluído", "ar": "تم", "hi": "हो गया", "fr": "Terminé"},
    "Cancel": {"zh-Hans": "取消", "zh-Hant": "取消", "ja": "キャンセル", "es": "Cancelar", "pt-BR": "Cancelar", "ar": "إلغاء", "hi": "रद्द करें", "fr": "Annuler"},
    "OK": {"zh-Hans": "好的", "zh-Hant": "好的", "ja": "OK", "es": "OK", "pt-BR": "OK", "ar": "موافق", "hi": "ठीक", "fr": "OK"},
    "Confirm": {"zh-Hans": "确认", "zh-Hant": "確認", "ja": "確認", "es": "Confirmar", "pt-BR": "Confirmar", "ar": "تأكيد", "hi": "पुष्टि", "fr": "Confirmer"},
    "Delete": {"zh-Hans": "删除", "zh-Hant": "刪除", "ja": "削除", "es": "Eliminar", "pt-BR": "Excluir", "ar": "حذف", "hi": "हटाएं", "fr": "Supprimer"},
    "Reset": {"zh-Hans": "重置", "zh-Hant": "重置", "ja": "リセット", "es": "Restablecer", "pt-BR": "Redefinir", "ar": "إعادة تعيين", "hi": "रीसेट", "fr": "Réinitialiser"},
    "Start": {"zh-Hans": "开始", "zh-Hant": "開始", "ja": "開始", "es": "Iniciar", "pt-BR": "Iniciar", "ar": "بدء", "hi": "शुरू", "fr": "Démarrer"},
    "Pause": {"zh-Hans": "暂停", "zh-Hant": "暫停", "ja": "一時停止", "es": "Pausar", "pt-BR": "Pausar", "ar": "إيقاف مؤقت", "hi": "रोकें", "fr": "Pause"},
    "Stop": {"zh-Hans": "停止", "zh-Hant": "停止", "ja": "停止", "es": "Detener", "pt-BR": "Parar", "ar": "إيقاف", "hi": "रोकें", "fr": "Arrêter"},
    "Continue": {"zh-Hans": "继续", "zh-Hant": "繼續", "ja": "再開", "es": "Continuar", "pt-BR": "Continuar", "ar": "متابعة", "hi": "जारी", "fr": "Continuer"},
    "Select": {"zh-Hans": "选择", "zh-Hant": "選擇", "ja": "選択", "es": "Seleccionar", "pt-BR": "Selecionar", "ar": "تحديد", "hi": "चुनें", "fr": "Sélectionner"},
    "Select All": {"zh-Hans": "全选", "zh-Hant": "全選", "ja": "すべて選択", "es": "Seleccionar todo", "pt-BR": "Selecionar tudo", "ar": "تحديد الكل", "hi": "सभी चुनें", "fr": "Tout sélectionner"},
    "Deselect All": {"zh-Hans": "取消全选", "zh-Hant": "取消全選", "ja": "選択解除", "es": "Deseleccionar todo", "pt-BR": "Desmarcar tudo", "ar": "إلغاء تحديد الكل", "hi": "सभी हटाएं", "fr": "Tout désélectionner"},
    "Share": {"zh-Hans": "分享", "zh-Hant": "分享", "ja": "共有", "es": "Compartir", "pt-BR": "Compartilhar", "ar": "مشاركة", "hi": "साझा", "fr": "Partager"},
    "Save": {"zh-Hans": "保存", "zh-Hant": "儲存", "ja": "保存", "es": "Guardar", "pt-BR": "Salvar", "ar": "حفظ", "hi": "सहेजें", "fr": "Enregistrer"},
    "Merge": {"zh-Hans": "合并", "zh-Hant": "合併", "ja": "統合", "es": "Combinar", "pt-BR": "Mesclar", "ar": "دمج", "hi": "मर्ज", "fr": "Fusionner"},
    "Language": {"zh-Hans": "语言", "zh-Hant": "語言", "ja": "言語", "es": "Idioma", "pt-BR": "Idioma", "ar": "اللغة", "hi": "भाषा", "fr": "Langue"},
    "System Default": {"zh-Hans": "跟随系统", "zh-Hant": "跟隨系統", "ja": "システムデフォルト", "es": "Predeterminado del sistema", "pt-BR": "Padrão do sistema", "ar": "افتراضي النظام", "hi": "सिस्टम डिफ़ॉल्ट", "fr": "Par défaut du système"},
    "Feedback": {"zh-Hans": "反馈", "zh-Hant": "意見回饋", "ja": "フィードバック", "es": "Comentarios", "pt-BR": "Feedback", "ar": "ملاحظات", "hi": "प्रतिक्रिया", "fr": "Commentaires"},
    "Support us": {"zh-Hans": "支持我们", "zh-Hant": "支持我們", "ja": "サポート", "es": "Apóyanos", "pt-BR": "Apoie-nos", "ar": "ادعمنا", "hi": "हमारा समर्थन", "fr": "Soutenez-nous"},
    "Privacy": {"zh-Hans": "隐私", "zh-Hant": "隱私", "ja": "プライバシー", "es": "Privacidad", "pt-BR": "Privacidade", "ar": "الخصوصية", "hi": "गोपनीयता", "fr": "Confidentialité"},
    "Terms of Use": {"zh-Hans": "使用协议", "zh-Hant": "使用協議", "ja": "利用規約", "es": "Términos de uso", "pt-BR": "Termos de uso", "ar": "شروط الاستخدام", "hi": "उपयोग की शर्तें", "fr": "Conditions d'utilisation"},
    "About": {"zh-Hans": "关于", "zh-Hant": "關於", "ja": "このアプリについて", "es": "Acerca de", "pt-BR": "Sobre", "ar": "حول", "hi": "परिचय", "fr": "À propos"},
    "Upgrade to Pro": {"zh-Hans": "升级 Pro 版本", "zh-Hant": "升級 Pro 版本", "ja": "Proにアップグレード", "es": "Actualizar a Pro", "pt-BR": "Atualizar para Pro", "ar": "الترقية إلى Pro", "hi": "Pro में अपग्रेड", "fr": "Passer à Pro"},
    "Outdoor track and altitude recorder": {"zh-Hans": "户外轨迹与海拔记录工具", "zh-Hant": "戶外軌跡與海拔記錄工具", "ja": "アウトドア轨迹・標高記録ツール", "es": "Registrador de rutas y altitud", "pt-BR": "Gravador de trilhas e altitude", "ar": "مسجل المسارات والارتفاع", "hi": "आउटडोर ट्रैक और ऊंचाई रिकॉर्डर", "fr": "Enregistreur de traces et d'altitude"},
    "Version": {"zh-Hans": "版本", "zh-Hant": "版本", "ja": "バージョン", "es": "Versión", "pt-BR": "Versão", "ar": "الإصدار", "hi": "संस्करण", "fr": "Version"},
    "Visit Website": {"zh-Hans": "访问官网", "zh-Hant": "造訪官網", "ja": "ウェブサイト", "es": "Visitar sitio web", "pt-BR": "Visitar site", "ar": "زيارة الموقع", "hi": "वेबसाइट", "fr": "Visiter le site"},
    "Compass": {"zh-Hans": "指南针", "zh-Hant": "指南針", "ja": "コンパス", "es": "Brújula", "pt-BR": "Bússola", "ar": "بوصلة", "hi": "कंपास", "fr": "Boussole"},
    "Altitude": {"zh-Hans": "海拔", "zh-Hant": "海拔", "ja": "標高", "es": "Altitud", "pt-BR": "Altitude", "ar": "الارتفاع", "hi": "ऊंचाई", "fr": "Altitude"},
    "Speed": {"zh-Hans": "测速", "zh-Hant": "測速", "ja": "速度", "es": "Velocímetro", "pt-BR": "Velocímetro", "ar": "سرعة", "hi": "गति", "fr": "Vitesse"},
    "Activity": {"zh-Hans": "运动", "zh-Hant": "運動", "ja": "アクティビティ", "es": "Actividad", "pt-BR": "Atividade", "ar": "نشاط", "hi": "गतिविधि", "fr": "Activité"},
    "Geo Camera": {"zh-Hans": "经纬相机", "zh-Hant": "經緯相機", "ja": "位置カメラ", "es": "Cámara geo", "pt-BR": "Câmera geo", "ar": "كاميرا الموقع", "hi": "जियो कैमरा", "fr": "Caméra geo"},
    "History": {"zh-Hans": "记录", "zh-Hant": "記錄", "ja": "履歴", "es": "Historial", "pt-BR": "Histórico", "ar": "السجل", "hi": "इतिहास", "fr": "Historique"},
    "Track History": {"zh-Hans": "轨迹记录", "zh-Hant": "軌跡記錄", "ja": "軌跡履歴", "es": "Historial de rutas", "pt-BR": "Histórico de trilhas", "ar": "سجل المسار", "hi": "ट्रैक इतिहास", "fr": "Historique des traces"},
    "No Tracks Yet": {"zh-Hans": "暂无轨迹", "zh-Hant": "暫無軌跡", "ja": "軌跡がありません", "es": "Sin rutas", "pt-BR": "Sem trilhas", "ar": "لا توجد مسارات", "hi": "कोई ट्रैक नहीं", "fr": "Aucune trace"},
    "Tracks appear here after you start an activity.": {"zh-Hans": "开始运动后，轨迹将自动出现在这里", "zh-Hant": "開始運動後，軌跡將自動出現在這裡", "ja": "アクティビティ開始後、ここに表示されます", "es": "Las rutas aparecerán aquí al iniciar una actividad.", "pt-BR": "As trilhas aparecerão aqui após iniciar uma atividade.", "ar": "ستظهر المسارات هنا بعد بدء النشاط.", "hi": "गतिविधि शुरू करने के बाद ट्रैक यहाँ दिखेंगे।", "fr": "Les traces apparaîtront ici après une activité."},
    "Delete Selected Tracks?": {"zh-Hans": "删除所选轨迹？", "zh-Hant": "刪除所選軌跡？", "ja": "選択した軌跡を削除しますか？", "es": "¿Eliminar rutas seleccionadas?", "pt-BR": "Excluir trilhas selecionadas?", "ar": "حذف المسارات المحددة؟", "hi": "चयनित ट्रैक हटाएं?", "fr": "Supprimer les traces sélectionnées ?"},
    "This will permanently delete %lld tracks and their GPX files.": {"zh-Hans": "将删除 %lld 条轨迹及其 GPX 文件，此操作不可恢复。", "zh-Hant": "將刪除 %lld 條軌跡及其 GPX 檔案，此操作不可恢復。", "ja": "%lld 件の軌跡とGPXファイルが完全に削除されます。", "es": "Se eliminarán permanentemente %lld rutas y sus archivos GPX.", "pt-BR": "Isso excluirá permanentemente %lld trilhas e seus arquivos GPX.", "ar": "سيتم حذف %lld مسارات وملفات GPX نهائياً.", "hi": "%lld ट्रैक और GPX फ़ाइलें स्थायी रूप से हटा दी जाएंगी।", "fr": "Cela supprimera définitivement %lld traces et leurs fichiers GPX."},
    "Merge as Memory": {"zh-Hans": "打包合并为回忆", "zh-Hant": "打包合併為回憶", "ja": "思い出として統合", "es": "Combinar como recuerdo", "pt-BR": "Mesclar como memória", "ar": "دمج كذكرى", "hi": "याद के रूप में मर्ज", "fr": "Fusionner en souvenir"},
    "e.g. Canada Trip": {"zh-Hans": "例如：加拿大旅游", "zh-Hant": "例如：加拿大旅遊", "ja": "例：カナダ旅行", "es": "ej. Viaje a Canadá", "pt-BR": "ex.: Viagem ao Canadá", "ar": "مثال: رحلة كندا", "hi": "उदा. कनाडा यात्रा", "fr": "ex. Voyage au Canada"},
    "Confirm Merge": {"zh-Hans": "确认合并", "zh-Hant": "確認合併", "ja": "統合を確認", "es": "Confirmar combinación", "pt-BR": "Confirmar mesclagem", "ar": "تأكيد الدمج", "hi": "मर्ज की पुष्टि", "fr": "Confirmer la fusion"},
    "Merge %lld tracks into one memory. Enter a new name.": {"zh-Hans": "将 %lld 条轨迹合并为一条回忆，请输入新名称。", "zh-Hant": "將 %lld 條軌跡合併為一條回憶，請輸入新名稱。", "ja": "%lld 件の軌跡を1つの思い出に統合します。新しい名前を入力してください。", "es": "Combinar %lld rutas en un recuerdo. Introduce un nombre.", "pt-BR": "Mesclar %lld trilhas em uma memória. Digite um nome.", "ar": "دمج %lld مسارات في ذكرى واحدة. أدخل اسماً جديداً.", "hi": "%lld ट्रैक को एक याद में मर्ज करें। नया नाम दर्ज करें।", "fr": "Fusionner %lld traces en un souvenir. Entrez un nom."},
    "Delete (%lld)": {"zh-Hans": "删除 (%lld)", "zh-Hant": "刪除 (%lld)", "ja": "削除 (%lld)", "es": "Eliminar (%lld)", "pt-BR": "Excluir (%lld)", "ar": "حذف (%lld)", "hi": "हटाएं (%lld)", "fr": "Supprimer (%lld)"},
    "Merge (%lld)": {"zh-Hans": "合并 (%lld)", "zh-Hant": "合併 (%lld)", "ja": "統合 (%lld)", "es": "Combinar (%lld)", "pt-BR": "Mesclar (%lld)", "ar": "دمج (%lld)", "hi": "मर्ज (%lld)", "fr": "Fusionner (%lld)"},
    "Merged": {"zh-Hans": "已合并", "zh-Hant": "已合併", "ja": "統合済み", "es": "Combinado", "pt-BR": "Mesclado", "ar": "تم الدمج", "hi": "मर्ज किया", "fr": "Fusionné"},
    "Merged Tracks": {"zh-Hans": "合并轨迹", "zh-Hant": "合併軌跡", "ja": "統合軌跡", "es": "Rutas combinadas", "pt-BR": "Trilhas mescladas", "ar": "مسارات مدمجة", "hi": "मर्ज ट्रैक", "fr": "Traces fusionnées"},
    "%@ Memory": {"zh-Hans": "%@ 回忆", "zh-Hant": "%@ 回憶", "ja": "%@ の思い出", "es": "Recuerdo %@", "pt-BR": "Memória %@", "ar": "ذكرى %@", "hi": "%@ याद", "fr": "Souvenir %@"},
    "Max %.0f m": {"zh-Hans": "最高 %.0f m", "zh-Hant": "最高 %.0f m", "ja": "最高 %.0f m", "es": "Máx %.0f m", "pt-BR": "Máx %.0f m", "ar": "أقصى %.0f m", "hi": "अधिकतम %.0f m", "fr": "Max %.0f m"},
    "Speed Test Active": {"zh-Hans": "测速中", "zh-Hant": "測速中", "ja": "測速中", "es": "Medición activa", "pt-BR": "Medição ativa", "ar": "قياس السرعة", "hi": "गति परीक्षण", "fr": "Mesure en cours"},
    "Start Speed Test": {"zh-Hans": "开始测速", "zh-Hant": "開始測速", "ja": "測速開始", "es": "Iniciar medición", "pt-BR": "Iniciar medição", "ar": "بدء قياس السرعة", "hi": "गति परीक्षण शुरू", "fr": "Démarrer la mesure"},
    "Stop Speed Test": {"zh-Hans": "停止测速", "zh-Hant": "停止測速", "ja": "測速停止", "es": "Detener medición", "pt-BR": "Parar medição", "ar": "إيقاف قياس السرعة", "hi": "गति परीक्षण रोकें", "fr": "Arrêter la mesure"},
    "This Session": {"zh-Hans": "本次测速", "zh-Hant": "本次測速", "ja": "今回の測定", "es": "Esta sesión", "pt-BR": "Esta sessão", "ar": "هذه الجلسة", "hi": "यह सत्र", "fr": "Cette session"},
    "Duration": {"zh-Hans": "时长", "zh-Hant": "時長", "ja": "時間", "es": "Duración", "pt-BR": "Duração", "ar": "المدة", "hi": "अवधि", "fr": "Durée"},
    "Average Speed": {"zh-Hans": "平均速度", "zh-Hant": "平均速度", "ja": "平均速度", "es": "Velocidad media", "pt-BR": "Velocidade média", "ar": "متوسط السرعة", "hi": "औसत गति", "fr": "Vitesse moyenne"},
    "Distance": {"zh-Hans": "路程", "zh-Hant": "路程", "ja": "距離", "es": "Distancia", "pt-BR": "Distância", "ar": "المسافة", "hi": "दूरी", "fr": "Distance"},
    "Max Speed": {"zh-Hans": "最大速度", "zh-Hant": "最大速度", "ja": "最高速度", "es": "Velocidad máxima", "pt-BR": "Velocidade máxima", "ar": "السرعة القصوى", "hi": "अधिकतम गति", "fr": "Vitesse max"},
    "Elevation Gain": {"zh-Hans": "累计爬升", "zh-Hant": "累計爬升", "ja": "累積上昇", "es": "Desnivel positivo", "pt-BR": "Ganho de elevação", "ar": "ارتفاع تراكمي", "hi": "कुल चढ़ाई", "fr": "Dénivelé positif"},
    "Driving": {"zh-Hans": "驾车", "zh-Hant": "駕車", "ja": "ドライブ", "es": "Conducción", "pt-BR": "Dirigindo", "ar": "قيادة", "hi": "ड्राइविंग", "fr": "Conduite"},
    "Cycling": {"zh-Hans": "骑行", "zh-Hant": "騎行", "ja": "サイクリング", "es": "Ciclismo", "pt-BR": "Ciclismo", "ar": "ركوب الدراجة", "hi": "साइकिल", "fr": "Vélo"},
    "Running": {"zh-Hans": "跑步", "zh-Hant": "跑步", "ja": "ランニング", "es": "Correr", "pt-BR": "Corrida", "ar": "الجري", "hi": "दौड़", "fr": "Course"},
    "Walking": {"zh-Hans": "步行", "zh-Hant": "步行", "ja": "ウォーキング", "es": "Caminata", "pt-BR": "Caminhada", "ar": "المشي", "hi": "पैदल", "fr": "Marche"},
    "Speedometer": {"zh-Hans": "速度表", "zh-Hant": "速度表", "ja": "速度計", "es": "Velocímetro", "pt-BR": "Velocímetro", "ar": "عداد السرعة", "hi": "स्पीडोमीटर", "fr": "Compteur de vitesse"},
    "Digital Compass": {"zh-Hans": "数字罗盘", "zh-Hant": "數位羅盤", "ja": "デジタルコンパス", "es": "Brújula digital", "pt-BR": "Bússola digital", "ar": "بوصلة رقمية", "hi": "डिजिटल कंपास", "fr": "Boussole numérique"},
    "Elevation": {"zh-Hans": "海拔", "zh-Hant": "海拔", "ja": "標高", "es": "Altitud", "pt-BR": "Elevação", "ar": "الارتفاع", "hi": "ऊंचाई", "fr": "Altitude"},
    "Air Pressure": {"zh-Hans": "大气压", "zh-Hant": "大氣壓", "ja": "気圧", "es": "Presión atmosférica", "pt-BR": "Pressão atmosférica", "ar": "الضغط الجوي", "hi": "वायु दाब", "fr": "Pression atmosphérique"},
    "Wind Direction": {"zh-Hans": "风向", "zh-Hant": "風向", "ja": "風向", "es": "Dirección del viento", "pt-BR": "Direção do vento", "ar": "اتجاه الرياح", "hi": "हवा की दिशा", "fr": "Direction du vent"},
    "Capture": {"zh-Hans": "拍摄", "zh-Hant": "拍攝", "ja": "撮影", "es": "Capturar", "pt-BR": "Capturar", "ar": "التقاط", "hi": "कैप्चर", "fr": "Capturer"},
    "No Captures Yet": {"zh-Hans": "暂无拍摄", "zh-Hant": "暫無拍攝", "ja": "撮影がありません", "es": "Sin capturas", "pt-BR": "Sem capturas", "ar": "لا توجد لقطات", "hi": "कोई कैप्चर नहीं", "fr": "Aucune capture"},
    "Photos and videos appear here after capture.": {"zh-Hans": "拍照或录像后会显示在这里", "zh-Hant": "拍照或錄影後會顯示在這裡", "ja": "撮影後ここに表示されます", "es": "Las fotos y videos aparecerán aquí.", "pt-BR": "Fotos e vídeos aparecerão aqui.", "ar": "ستظهر الصور والفيديوهات هنا.", "hi": "फ़ोटो और वीडियो यहाँ दिखेंगे।", "fr": "Les photos et vidéos apparaîtront ici."},
    "Delete Selected Media?": {"zh-Hans": "删除所选媒体？", "zh-Hant": "刪除所選媒體？", "ja": "選択したメディアを削除しますか？", "es": "¿Eliminar medios seleccionados?", "pt-BR": "Excluir mídia selecionada?", "ar": "حذف الوسائط المحددة؟", "hi": "हिन्दी", "fr": "Supprimer les médias sélectionnés ?"},
    "Sort": {"zh-Hans": "排序", "zh-Hant": "排序", "ja": "並べ替え", "es": "Ordenar", "pt-BR": "Ordenar", "ar": "ترتيب", "hi": "क्रमबद्ध", "fr": "Trier"},
    "%lld selected": {"zh-Hans": "已选 %lld", "zh-Hant": "已選 %lld", "ja": "%lld 件選択", "es": "%lld seleccionados", "pt-BR": "%lld selecionados", "ar": "%lld محدد", "hi": "%lld चयनित", "fr": "%lld sélectionnés"},
    "Deleted": {"zh-Hans": "已删除", "zh-Hant": "已刪除", "ja": "削除しました", "es": "Eliminado", "pt-BR": "Excluído", "ar": "تم الحذف", "hi": "हटाया गया", "fr": "Supprimé"},
    "Saved to Photos": {"zh-Hans": "已保存到相册", "zh-Hant": "已儲存到相簿", "ja": "写真に保存しました", "es": "Guardado en Fotos", "pt-BR": "Salvo em Fotos", "ar": "تم الحفظ في الصور", "hi": "फ़ोटो में सहेजा", "fr": "Enregistré dans Photos"},
    "Team %@": {"zh-Hans": "队伍 %@", "zh-Hant": "隊伍 %@", "ja": "チーム %@", "es": "Equipo %@", "pt-BR": "Equipe %@", "ar": "فريق %@", "hi": "टीम %@", "fr": "Équipe %@"},
    "Face to Face Team Up": {"zh-Hans": "面对面组队", "zh-Hant": "面對面組隊", "ja": "対面でチーム", "es": "Equipo en persona", "pt-BR": "Equipe presencial", "ar": "فريق وجهاً لوجه", "hi": "सामने से टीम", "fr": "Équipe en personne"},
    "Leave": {"zh-Hans": "退出", "zh-Hant": "退出", "ja": "退出", "es": "Salir", "pt-BR": "Sair", "ar": "مغادرة", "hi": "छोड़ें", "fr": "Quitter"},
    "Leave Team": {"zh-Hans": "退出队伍", "zh-Hant": "退出隊伍", "ja": "チームを退出", "es": "Salir del equipo", "pt-BR": "Sair da equipe", "ar": "مغادرة الفريق", "hi": "टीम छोड़ें", "fr": "Quitter l'équipe"},
    "Disconnected": {"zh-Hans": "连接中断", "zh-Hant": "連線中斷", "ja": "切断", "es": "Desconectado", "pt-BR": "Desconectado", "ar": "انقطع الاتصال", "hi": "डिस्कनेक्ट", "fr": "Déconnecté"},
    "Connecting…": {"zh-Hans": "连接中…", "zh-Hant": "連線中…", "ja": "接続中…", "es": "Conectando…", "pt-BR": "Conectando…", "ar": "جاري الاتصال…", "hi": "कनेक्ट हो रहा…", "fr": "Connexion…"},
    "%lld online": {"zh-Hans": "%lld 人在线", "zh-Hant": "%lld 人在線", "ja": "%lld 人オンライン", "es": "%lld en línea", "pt-BR": "%lld online", "ar": "%lld متصل", "hi": "%lld ऑनलाइन", "fr": "%lld en ligne"},
    "You Are Now Host": {"zh-Hans": "你自动成为房主", "zh-Hant": "你自動成為房主", "ja": "あなたがホストになりました", "es": "Ahora eres anfitrión", "pt-BR": "Você é o anfitrião", "ar": "أنت المضيف الآن", "hi": "अब आप होस्ट हैं", "fr": "Vous êtes l'hôte"},
    "The previous host left. You now control the team.": {"zh-Hans": "原房主已退出，你已接管队伍控制。", "zh-Hant": "原房主已退出，你已接管隊伍控制。", "ja": "前のホストが退出しました。チームを管理します。", "es": "El anfitrión anterior salió. Ahora controlas el equipo.", "pt-BR": "O anfitrião anterior saiu. Você controla a equipe.", "ar": "غادر المضيف السابق. أنت تتحكم بالفريق.", "hi": "पिछला होस्ट चला गया। अब आप नियंत्रण में हैं।", "fr": "L'hôte précédent est parti. Vous contrôlez l'équipe."},
    "Reset Activity Session": {"zh-Hans": "重置运动会话", "zh-Hant": "重置運動會話", "ja": "アクティビティをリセット", "es": "Restablecer sesión", "pt-BR": "Redefinir sessão", "ar": "إعادة تعيين الجلسة", "hi": "सत्र रीसेट", "fr": "Réinitialiser la session"},
    "This resets speed, duration, and distance for all members.": {"zh-Hans": "将同步重置所有成员的速度、时长与行程数据。", "zh-Hant": "將同步重置所有成員的速度、時長與行程數據。", "ja": "全メンバーの速度・時間・距離がリセットされます。", "es": "Restablece velocidad, duración y distancia de todos.", "pt-BR": "Redefine velocidade, duração e distância de todos.", "ar": "يعيد تعيين السرعة والمدة والمسافة للجميع.", "hi": "सभी सदस्यों की गति, अवधि, दूरी रीसेट होगी।", "fr": "Réinitialise vitesse, durée et distance pour tous."},
    "Track Saved": {"zh-Hans": "轨迹已保存", "zh-Hant": "軌跡已儲存", "ja": "軌跡を保存しました", "es": "Ruta guardada", "pt-BR": "Trilha salva", "ar": "تم حفظ المسار", "hi": "ट्रैक सहेजा", "fr": "Trace enregistrée"},
    "Edit Nickname": {"zh-Hans": "修改昵称", "zh-Hant": "修改暱稱", "ja": "ニックネーム編集", "es": "Editar apodo", "pt-BR": "Editar apelido", "ar": "تعديل الاسم", "hi": "उपनाम संपादित", "fr": "Modifier le surnom"},
    "Face to Face Team Up": {"zh-Hans": "面对面组队", "zh-Hant": "面對面組隊", "ja": "対面でチーム", "es": "Equipo en persona", "pt-BR": "Equipe presencial", "ar": "فريق وجهاً لوجه", "hi": "सामने से टीम", "fr": "Équipe en personne"},
    "N": {"zh-Hans": "北", "zh-Hant": "北", "ja": "北", "es": "N", "pt-BR": "N", "ar": "ش", "hi": "उ", "fr": "N"},
    "NE": {"zh-Hans": "东北", "zh-Hant": "東北", "ja": "北東", "es": "NE", "pt-BR": "NE", "ar": "شش", "hi": "उपू", "fr": "NE"},
    "E": {"zh-Hans": "东", "zh-Hant": "東", "ja": "東", "es": "E", "pt-BR": "L", "ar": "شر", "hi": "पू", "fr": "E"},
    "SE": {"zh-Hans": "东南", "zh-Hant": "東南", "ja": "南東", "es": "SE", "pt-BR": "SE", "ar": "جش", "hi": "दपू", "fr": "SE"},
    "S": {"zh-Hans": "南", "zh-Hant": "南", "ja": "南", "es": "S", "pt-BR": "S", "ar": "ج", "hi": "द", "fr": "S"},
    "SW": {"zh-Hans": "西南", "zh-Hant": "西南", "ja": "南西", "es": "SO", "pt-BR": "SO", "ar": "جغ", "hi": "दप", "fr": "SO"},
    "W": {"zh-Hans": "西", "zh-Hant": "西", "ja": "西", "es": "O", "pt-BR": "O", "ar": "غ", "hi": "प", "fr": "O"},
    "NW": {"zh-Hans": "西北", "zh-Hant": "西北", "ja": "北西", "es": "NO", "pt-BR": "NO", "ar": "شغ", "hi": "उप", "fr": "NO"},
    "N Wind": {"zh-Hans": "北风", "zh-Hant": "北風", "ja": "北風", "es": "Viento N", "pt-BR": "Vento N", "ar": "رياح شمالية", "hi": "उत्तर हवा", "fr": "Vent N"},
    "NE Wind": {"zh-Hans": "东北风", "zh-Hant": "東北風", "ja": "北東風", "es": "Viento NE", "pt-BR": "Vento NE", "ar": "رياح شمال شرق", "hi": "उपू हवा", "fr": "Vent NE"},
    "E Wind": {"zh-Hans": "东风", "zh-Hant": "東風", "ja": "東風", "es": "Viento E", "pt-BR": "Vento L", "ar": "رياح شرقية", "hi": "पूर्व हवा", "fr": "Vent E"},
    "SE Wind": {"zh-Hans": "东南风", "zh-Hant": "東南風", "ja": "南東風", "es": "Viento SE", "pt-BR": "Vento SE", "ar": "رياح جنوب شرق", "hi": "दक्षिण-पूर्व हवा", "fr": "Vent SE"},
    "S Wind": {"zh-Hans": "南风", "zh-Hant": "南風", "ja": "南風", "es": "Viento S", "pt-BR": "Vento S", "ar": "رياح جنوبية", "hi": "दक्षिण हवा", "fr": "Vent S"},
    "SW Wind": {"zh-Hans": "西南风", "zh-Hant": "西南風", "ja": "南西風", "es": "Viento SO", "pt-BR": "Vento SO", "ar": "رياح جنوب غرب", "hi": "दक्षिण-पश्चिम हवा", "fr": "Vent SO"},
    "W Wind": {"zh-Hans": "西风", "zh-Hant": "西風", "ja": "西風", "es": "Viento O", "pt-BR": "Vento O", "ar": "رياح غربية", "hi": "पश्चिम हवा", "fr": "Vent O"},
    "NW Wind": {"zh-Hans": "西北风", "zh-Hant": "西北風", "ja": "北西風", "es": "Viento NO", "pt-BR": "Viento NO", "ar": "رياح شمال غرب", "hi": "उत्तर-पश्चिम हवा", "fr": "Vent NO"},
    "East Longitude": {"zh-Hans": "东经", "zh-Hant": "東經", "ja": "東経", "es": "Longitud E", "pt-BR": "Longitude E", "ar": "خط طول شرقي", "hi": "पूर्व देशांतर", "fr": "Longitude E"},
    "West Longitude": {"zh-Hans": "西经", "zh-Hant": "西經", "ja": "西経", "es": "Longitud O", "pt-BR": "Longitude O", "ar": "خط طول غربي", "hi": "पश्चिम देशांतर", "fr": "Longitude O"},
    "North Latitude": {"zh-Hans": "北纬", "zh-Hant": "北緯", "ja": "北緯", "es": "Latitud N", "pt-BR": "Latitude N", "ar": "خط عرض شمالي", "hi": "उत्तर अक्षांश", "fr": "Latitude N"},
    "South Latitude": {"zh-Hans": "南纬", "zh-Hant": "南緯", "ja": "南緯", "es": "Latitud S", "pt-BR": "Latitude S", "ar": "خط عرض جنوبي", "hi": "दक्षिण अक्षांश", "fr": "Latitude S"},
    "Coordinates": {"zh-Hans": "经纬度", "zh-Hant": "經緯度", "ja": "座標", "es": "Coordenadas", "pt-BR": "Coordenadas", "ar": "الإحداثيات", "hi": "निर्देशांक", "fr": "Coordonnées"},
    "Fetching data…": {"zh-Hans": "正在获取数据…", "zh-Hant": "正在取得資料…", "ja": "データ取得中…", "es": "Obteniendo datos…", "pt-BR": "Obtendo dados…", "ar": "جاري جلب البيانات…", "hi": "डेटा प्राप्त…", "fr": "Récupération des données…"},
    "No Track Data": {"zh-Hans": "无轨迹数据", "zh-Hant": "無軌跡數據", "ja": "軌跡データなし", "es": "Sin datos de ruta", "pt-BR": "Sem dados de trilha", "ar": "لا توجد بيانات مسار", "hi": "कोई ट्रैक डेटा नहीं", "fr": "Aucune donnée de trace"},
    "Could not load GPS track for this record.": {"zh-Hans": "未能加载此记录的 GPS 轨迹", "zh-Hant": "未能載入此記錄的 GPS 軌跡", "ja": "この記録のGPS軌跡を読み込めませんでした", "es": "No se pudo cargar la ruta GPS.", "pt-BR": "Não foi possível carregar a trilha GPS.", "ar": "تعذر تحميل مسار GPS.", "hi": "GPS ट्रैक लोड नहीं हो सका।", "fr": "Impossible de charger la trace GPS."},
    "Ascent": {"zh-Hans": "爬升", "zh-Hant": "爬升", "ja": "上昇", "es": "Ascenso", "pt-BR": "Ascensão", "ar": "صعود", "hi": "चढ़ाई", "fr": "Ascension"},
    "Highest": {"zh-Hans": "最高", "zh-Hant": "最高", "ja": "最高", "es": "Máximo", "pt-BR": "Máximo", "ar": "الأعلى", "hi": "उच्चतम", "fr": "Maximum"},
    "Start Point": {"zh-Hans": "起点", "zh-Hant": "起點", "ja": "起点", "es": "Inicio", "pt-BR": "Início", "ar": "نقطة البداية", "hi": "प्रारंभ", "fr": "Départ"},
    "End Point": {"zh-Hans": "终点", "zh-Hant": "終點", "ja": "終点", "es": "Fin", "pt-BR": "Fim", "ar": "نقطة النهاية", "hi": "अंत", "fr": "Arrivée"},
    "Track too short, not saved": {"zh-Hans": "轨迹太短，未保存", "zh-Hant": "軌跡太短，未儲存", "ja": "軌跡が短すぎて保存されませんでした", "es": "Ruta demasiado corta, no guardada", "pt-BR": "Trilha curta demais, não salva", "ar": "المسار قصير جداً، لم يُحفظ", "hi": "ट्रैक बहुत छोटा, सहेजा नहीं", "fr": "Trace trop courte, non enregistrée"},
    "Failed to write track file": {"zh-Hans": "轨迹文件写入失败", "zh-Hant": "軌跡檔案寫入失敗", "ja": "軌跡ファイルの書き込みに失敗", "es": "Error al escribir archivo", "pt-BR": "Falha ao gravar arquivo", "ar": "فشل كتابة ملف المسار", "hi": "फ़ाइल लिखने में विफल", "fr": "Échec d'écriture du fichier"},
    "Failed to save track": {"zh-Hans": "轨迹保存失败", "zh-Hant": "軌跡儲存失敗", "ja": "軌跡の保存に失敗", "es": "Error al guardar ruta", "pt-BR": "Falha ao salvar trilha", "ar": "فشل حفظ المسار", "hi": "ट्रैक सहेजने में विफल", "fr": "Échec de l'enregistrement"},
    "Leave Team?": {"zh-Hans": "退出队伍？", "zh-Hant": "退出隊伍？", "ja": "チームを退出しますか？", "es": "¿Salir del equipo?", "pt-BR": "Sair da equipe?", "ar": "مغادرة الفريق؟", "hi": "टीम छोड़ें?", "fr": "Quitter l'équipe ?"},
    "After leaving, the host role passes to the next member.": {"zh-Hans": "退出后房主将自动移交给下一位队员，其余成员可继续组队。", "zh-Hant": "退出後房主將自動移交給下一位隊員，其餘成員可繼續組隊。", "ja": "退出後、ホストは次のメンバーに移ります。", "es": "Al salir, el anfitrión pasa al siguiente miembro.", "pt-BR": "Ao sair, o anfitrião passa ao próximo membro.", "ar": "بعد المغادرة، ينتقل الدور للعضو التالي.", "hi": "छोड़ने पर होस्ट अगले सदस्य को मिलेगा।", "fr": "En quittant, l'hôte passe au membre suivant."},
    "You will leave the room.": {"zh-Hans": "退出后你将离开房间。", "zh-Hant": "退出後你將離開房間。", "ja": "退出するとルームを離れます。", "es": "Saldrás de la sala.", "pt-BR": "Você sairá da sala.", "ar": "ستغادر الغرفة.", "hi": "आप कमरा छोड़ देंगे।", "fr": "Vous quitterez la salle."},
    "You will leave the current team.": {"zh-Hans": "退出后将离开当前队伍。", "zh-Hant": "退出後將離開當前隊伍。", "ja": "現在のチームを離れます。", "es": "Dejarás el equipo actual.", "pt-BR": "Você deixará a equipe atual.", "ar": "ستغادر الفريق الحالي.", "hi": "आप वर्तमान टीम छोड़ देंगे।", "fr": "Vous quitterez l'équipe actuelle."},
    "Cannot connect to team service. Check your network.": {"zh-Hans": "无法连接组队服务，请检查网络后重试", "zh-Hant": "無法連線組隊服務，請檢查網路後重試", "ja": "チームサービスに接続できません。ネットワークを確認してください。", "es": "No se puede conectar. Comprueba la red.", "pt-BR": "Não foi possível conectar. Verifique a rede.", "ar": "تعذر الاتصال. تحقق من الشبكة.", "hi": "कनेक्ट नहीं हो सका। नेटवर्क जांचें।", "fr": "Connexion impossible. Vérifiez le réseau."},
    "Clear": {"zh-Hans": "晴", "zh-Hant": "晴", "ja": "晴れ", "es": "Despejado", "pt-BR": "Limpo", "ar": "صافٍ", "hi": "साफ", "fr": "Clair"},
    "Cloudy": {"zh-Hans": "多云", "zh-Hant": "多雲", "ja": "曇り", "es": "Nublado", "pt-BR": "Nublado", "ar": "غائم", "hi": "बादल", "fr": "Nuageux"},
    "Overcast": {"zh-Hans": "阴", "zh-Hant": "陰", "ja": "くもり", "es": "Cubierto", "pt-BR": "Encoberto", "ar": "ملبد", "hi": "घटाटोप", "fr": "Couvert"},
    "Light Rain": {"zh-Hans": "小雨", "zh-Hant": "小雨", "ja": "小雨", "es": "Lluvia ligera", "pt-BR": "Chuva fraca", "ar": "مطر خفيف", "hi": "हल्की बारिश", "fr": "Pluie fine"},
    "Thunderstorm": {"zh-Hans": "雷雨", "zh-Hant": "雷雨", "ja": "雷雨", "es": "Tormenta", "pt-BR": "Tempestade", "ar": "عاصفة رعدية", "hi": "आंधी", "fr": "Orage"},
    "Snow": {"zh-Hans": "雪", "zh-Hant": "雪", "ja": "雪", "es": "Nieve", "pt-BR": "Neve", "ar": "ثلج", "hi": "बर्फ", "fr": "Neige"},
    "Fog": {"zh-Hans": "雾", "zh-Hant": "霧", "ja": "霧", "es": "Niebla", "pt-BR": "Nevoeiro", "ar": "ضباب", "hi": "कोहरा", "fr": "Brouillard"},
    "Windy": {"zh-Hans": "大风", "zh-Hant": "大風", "ja": "強風", "es": "Ventoso", "pt-BR": "Ventoso", "ar": "رياح قوية", "hi": "तेज़ हवा", "fr": "Venteux"},
    "Hail": {"zh-Hans": "冰雹", "zh-Hant": "冰雹", "ja": "雹", "es": "Granizo", "pt-BR": "Granizo", "ar": "برد", "hi": "ओले", "fr": "Grêle"},
    "Freezing Rain": {"zh-Hans": "冻雨", "zh-Hant": "凍雨", "ja": "凍雨", "es": "Lluvia helada", "pt-BR": "Chuva congelante", "ar": "مطر متجمد", "hi": "जमी बारिश", "fr": "Pluie verglaçante"},
    "Storm": {"zh-Hans": "风暴", "zh-Hant": "風暴", "ja": "嵐", "es": "Tormenta", "pt-BR": "Tempestade", "ar": "عاصفة", "hi": "तूफान", "fr": "Tempête"},
    "Frigid": {"zh-Hans": "严寒", "zh-Hant": "嚴寒", "ja": "極寒", "es": "Gélido", "pt-BR": "Gélido", "ar": "قارس", "hi": "अत्यंत ठंड", "fr": "Glacial"},
    "Dust": {"zh-Hans": "沙尘", "zh-Hant": "沙塵", "ja": "砂塵", "es": "Polvo", "pt-BR": "Poeira", "ar": "غبار", "hi": "धूल", "fr": "Poussière"},
    "Unknown": {"zh-Hans": "未知", "zh-Hant": "未知", "ja": "不明", "es": "Desconocido", "pt-BR": "Desconhecido", "ar": "غير معروف", "hi": "अज्ञात", "fr": "Inconnu"},
    "Photo capture failed": {"zh-Hans": "拍照失败", "zh-Hant": "拍照失敗", "ja": "撮影に失敗", "es": "Error al capturar", "pt-BR": "Falha na captura", "ar": "فشل التقاط الصورة", "hi": "फ़ोटो विफल", "fr": "Échec de la capture"},
    "Environment Mode": {"zh-Hans": "环境模式", "zh-Hant": "環境模式", "ja": "環境モード", "es": "Modo entorno", "pt-BR": "Modo ambiente", "ar": "وضع البيئة", "hi": "पर्यावरण मोड", "fr": "Mode environnement"},
    "Manual": {"zh-Hans": "手动", "zh-Hant": "手動", "ja": "手動", "es": "Manual", "pt-BR": "Manual", "ar": "يدوي", "hi": "मैनुअल", "fr": "Manuel"},
    "Auto": {"zh-Hans": "自动", "zh-Hant": "自動", "ja": "自動", "es": "Auto", "pt-BR": "Auto", "ar": "تلقائي", "hi": "ऑटो", "fr": "Auto"},
    "Indoor Floor": {"zh-Hans": "室内楼层", "zh-Hant": "室內樓層", "ja": "室内階", "es": "Piso interior", "pt-BR": "Andar interno", "ar": "طابق داخلي", "hi": "इनडोर फ़्लोर", "fr": "Étage intérieur"},
    "Calibrated": {"zh-Hans": "已校准", "zh-Hant": "已校準", "ja": "キャリブレーション済", "es": "Calibrado", "pt-BR": "Calibrado", "ar": "معاير", "hi": "कैलिब्रेटेड", "fr": "Calibré"},
    "Needs Calibration": {"zh-Hans": "待校准", "zh-Hant": "待校準", "ja": "要キャリブレーション", "es": "Necesita calibración", "pt-BR": "Precisa calibrar", "ar": "يحتاج معايرة", "hi": "कैलिब्रेशन जरूरी", "fr": "Calibration requise"},
    "Set Current Floor": {"zh-Hans": "设定当前楼层", "zh-Hant": "設定當前樓層", "ja": "現在の階を設定", "es": "Establecer piso actual", "pt-BR": "Definir andar atual", "ar": "تعيين الطابق الحالي", "hi": "वर्तमान मंजिल सेट", "fr": "Définir l'étage actuel"},
    "Recalibrate Floor": {"zh-Hans": "重新校准楼层", "zh-Hant": "重新校準樓層", "ja": "階を再キャリブレーション", "es": "Recalibrar piso", "pt-BR": "Recalibrar andar", "ar": "إعادة معايرة الطابق", "hi": "फ़्लोर पुनः कैलिब्रेट", "fr": "Recalibrer l'étage"},
    "Floor %lld": {"zh-Hans": "%lld 楼", "zh-Hant": "%lld 樓", "ja": "%lld 階", "es": "Piso %lld", "pt-BR": "Andar %lld", "ar": "طابق %lld", "hi": "मंजिल %lld", "fr": "Étage %lld"},
    "Not Set": {"zh-Hans": "待设定", "zh-Hant": "待設定", "ja": "未設定", "es": "Sin configurar", "pt-BR": "Não definido", "ar": "غير محدد", "hi": "सेट नहीं", "fr": "Non défini"},
    "Estimating…": {"zh-Hans": "推算中…", "zh-Hant": "推算中…", "ja": "推定中…", "es": "Estimando…", "pt-BR": "Estimando…", "ar": "جاري التقدير…", "hi": "अनुमान…", "fr": "Estimation…"},
    "Loading data…": {"zh-Hans": "正在获取数据…", "zh-Hant": "正在取得資料…", "ja": "データ取得中…", "es": "Cargando datos…", "pt-BR": "Carregando dados…", "ar": "جاري التحميل…", "hi": "लोड हो रहा…", "fr": "Chargement…"},
}

for _key, _zh in EXTRA_ZH.items():
    entry = TRANSLATIONS.setdefault(_key, {})
    entry.setdefault("zh-Hans", _zh)
    entry.setdefault("zh-Hant", _zh)


def resolve_translation(key: str, locale: str) -> str:
    trans = TRANSLATIONS.get(key, {})
    if locale == "en":
        return key
    if locale in trans:
        return trans[locale]
    if locale == "zh-Hant" and "zh-Hans" in trans:
        return trans["zh-Hans"]
    return key


def build_entry(key: str) -> dict:
    locs = {}
    for locale in LOCALES:
        locs[locale] = {
            "stringUnit": {
                "state": "translated",
                "value": resolve_translation(key, locale),
            }
        }
    return {"localizations": locs}


def collect_keys_from_codebase(root: Path) -> set[str]:
    import re

    pattern = re.compile(r'L10n\.(?:t|format)\("([^"\\]+)"')
    keys: set[str] = set()
    for path in root.rglob("*.swift"):
        text = path.read_text(encoding="utf-8")
        keys.update(pattern.findall(text))
    return keys


def main():
    project_root = Path(__file__).resolve().parents[1]
    swift_root = project_root / "AltiPin"
    all_keys = set(TRANSLATIONS.keys()) | collect_keys_from_codebase(swift_root)
    strings = {key: build_entry(key) for key in sorted(all_keys)}
    catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    out = swift_root / "Resources" / "Localizable.xcstrings"
    out.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(strings)} keys to {out}")

if __name__ == "__main__":
    main()
