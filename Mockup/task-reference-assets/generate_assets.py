"""Original, synthetic Japanese inquiry-management UI reference images.

No customer screenshot or third-party imagery is used. These raster previews
illustrate task reference media; they are not a live OPC product screen.
Requires Pillow and Windows Yu Gothic fonts. Run from any working directory.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent
SCALE = 2
W, H = 1200, 750
C = {
    'canvas': '#F4F7F6', 'white': '#FFFFFF', 'ink': '#203C34',
    'muted': '#71857D', 'line': '#E4ECE8', 'green': '#158267',
    'pale': '#E8F5EF', 'nav': '#17392F', 'navmuted': '#A8C2B7',
    'blue': '#EAF1FA', 'blueink': '#3C6899', 'amber': '#FFF3DC',
    'amberink': '#976919',
}


def font(size=16, bold=False):
    return ImageFont.truetype(
        'C:/Windows/Fonts/YuGothB.ttc' if bold else 'C:/Windows/Fonts/YuGothR.ttc',
        int(size * SCALE),
    )


def rect(box, fill, radius=0, outline=None):
    box = tuple(int(v * SCALE) for v in box)
    if radius:
        d.rounded_rectangle(box, radius=radius*SCALE, fill=fill,
                            outline=outline, width=SCALE)
    else:
        d.rectangle(box, fill=fill, outline=outline, width=SCALE)


def text(x, y, value, size=16, color=None, bold=False):
    d.text((x*SCALE, y*SCALE), value, font=font(size, bold),
           fill=color or C['ink'], anchor='lt')


def line(x1, y1, x2, y2, color=None, width=1):
    d.line((x1*SCALE, y1*SCALE, x2*SCALE, y2*SCALE),
           fill=color or C['line'], width=width*SCALE)


def pill(x, y, label, fill=None, ink=None, width=None):
    width = width or int(d.textlength(label, font=font(12, True))/SCALE) + 24
    rect((x,y,x+width,y+28), fill or C['pale'], 14)
    text(x+12,y+7,label,12,ink or C['green'],True)


def button(x,y,width,label,primary=False):
    rect((x,y,x+width,y+40), C['green'] if primary else C['white'], 8,
         None if primary else C['line'])
    dropdown='▾' in label
    label=label.replace('  ▾','')
    tw=d.textlength(label,font=font(14,True))/SCALE
    text(x+(width-tw)/2-(8 if dropdown else 0),y+12,label,14,C['white'] if primary else C['ink'],True)
    if dropdown:
        line(x+width-23,y+18,x+width-19,y+22,C['ink'])
        line(x+width-19,y+22,x+width-15,y+18,C['ink'])


def sidebar(active):
    rect((0,0,218,H),C['nav'])
    rect((24,27,60,63),'#2AAB80',10)
    text(32,37,'O',20,C['white'],True)
    text(73,31,'INBOX',20,C['white'],True)
    text(74,55,'お問い合わせ管理',10,C['navmuted'])
    text(27,111,'ワークスペース',11,C['navmuted'])
    items=['ダッシュボード','お問い合わせ','対応カレンダー','レポート','設定']
    for i,label in enumerate(items):
        y=142+i*52
        selected=i==active
        if selected: rect((16,y-5,202,y+39),'#285447',8)
        color='#79DBB5' if selected else C['navmuted']
        rect((29,y+8,44,y+23),color,3)
        rect((33,y+12,40,y+19),C['nav'] if not selected else '#285447',1)
        text(56,y+9,label,14,C['white'] if selected else C['navmuted'],selected)
        if i==1:
            rect((170,y+6,193,y+28),'#39745F',6)
            text(175,y+11,'12',11,C['white'],True)
    rect((16,579,202,656),'#224B3D',12)
    text(29,594,'チームで対応を整理',13,C['white'],True)
    text(29,619,'状況を共有して、見落としを防ぐ',10,C['navmuted'])
    line(22,683,196,683,'#305044')
    rect((25,700,51,726),'#48735F',13)
    text(31,707,'S',12,C['white'],True)
    text(63,698,'サンプルチーム',12,C['white'],True)
    text(63,716,'管理者',10,C['navmuted'])


def header(crumb):
    rect((218,0,W,74),C['white'])
    line(218,74,W,74)
    text(250,30,crumb,13,C['muted'])
    rect((976,24,1086,50),C['canvas'],6)
    text(990,31,'日本語',11,C['muted'])
    line(1045,34,1049,38,C['muted'])
    line(1049,38,1053,34,C['muted'])
    rect((1110,22,1144,56),C['pale'],17)
    text(1121,32,'S',14,C['green'],True)
    rect((1170,31,1174,45),C['muted'],2)


def create_base():
    global im,d
    im=Image.new('RGB',(W*SCALE,H*SCALE),C['canvas'])
    d=ImageDraw.Draw(im)
    sidebar(1)


def save(name):
    im.resize((W,H),Image.Resampling.LANCZOS).save(OUT/name,optimize=True)


create_base()
header('ワークスペース   /   お問い合わせ')
text(250,106,'お問い合わせ',27,bold=True)
text(250,146,'お客様からのご相談を、一か所で管理。',13,C['muted'])
button(994,109,170,'＋  新規お問い合わせ',True)

metrics=[('すべての相談','24','今月の受付'),('未対応','12','優先して確認'),('対応中','8','チームで対応中'),('解決済み','4','今月の完了')]
for i,(label,value,note) in enumerate(metrics):
    x=250+i*234
    rect((x,190,x+216,302),C['white'],12, C['line'])
    text(x+18,207,label,13,C['muted'])
    text(x+18,237,value,32,C['green'] if i==1 else C['ink'],True)
    text(x+85,259,note,11,C['muted'])
    if i==1: rect((x,190,x+216,194),'#3BB889',2)

rect((250,326,1168,704),C['white'],12,C['line'])
text(270,348,'一覧',15,C['green'],True)
text(339,348,'ボード',15,C['muted'])
line(269,378,302,378,C['green'],3)
line(250,379,1168,379)
rect((270,396,704,436),C['canvas'],7,C['line'])
text(286,409,'キーワードで検索',13,C['muted'])
button(722,396,134,'ステータス  ▾')
button(872,396,133,'担当チーム  ▾')
text(1073,410,'24 件',12,C['muted'])
rect((251,454,1167,495),'#F8FAF9')
for x,label in [(272,'件名'),(699,'カテゴリ'),(850,'ステータス'),(994,'更新日')]:
    text(x,469,label,11,C['muted'],True)
rows=[
    ('商品についてのお問い合わせ','サンプル案件 A ・ INQ-024','商品・サービス','未対応','2026/10/13'),
    ('お見積もりのご相談','サンプル案件 B ・ INQ-023','見積もり','対応中','2026/10/13'),
    ('アカウント設定のご質問','サンプル案件 C ・ INQ-022','ご利用方法','対応中','2026/10/12'),
]
for i,(title,sub,cat,status,date) in enumerate(rows):
    y=508+i*57
    text(271,y,title,14,bold=True)
    text(271,y+22,sub,10,C['muted'])
    text(699,y+8,cat,12,C['muted'])
    pill(849,y+1,status,C['amber'] if i==0 else C['blue'],C['amberink'] if i==0 else C['blueink'],72)
    text(994,y+9,date,11,C['muted'])
    text(1140,y+8,'›',17,C['muted'])
    line(270,y+47,1150,y+47)
text(271,686,'1–3 / 24 件',10,C['muted'])
text(1051,686,'‹      1      2      ›',11,C['muted'])
save('inquiry-overview.png')

create_base()
header('お問い合わせ   /   INQ-024')
text(250,103,'←  お問い合わせ一覧',12,C['green'],True)
text(250,137,'商品についてのお問い合わせ',25,bold=True)
text(250,179,'INQ-024   ・   受付 2026/10/13 09:30 JST',12,C['muted'])
button(1008,136,156,'対応を開始する',True)

rect((250,222,824,429),C['white'],12,C['line'])
text(272,244,'お問い合わせ内容',16,bold=True)
pill(696,239,'商品・サービス',width=108)
line(271,282,802,282)
text(272,305,'サンプル案件 A',13,C['green'],True)
for i,t in enumerate([
    '新しいサービスの導入について相談したいです。',
    '現在の業務フローを共有したうえで、必要な機能と',
    '導入までの進め方を教えていただけますか。',
]): text(272,339+i*26,t,14)

rect((846,222,1168,534),C['white'],12,C['line'])
text(867,244,'対応情報',16,bold=True)
line(866,282,1147,282)
text(868,303,'ステータス',12,C['muted'])
pill(1001,295,'未対応',C['amber'],C['amberink'],77)
text(868,352,'担当チーム',12,C['muted'])
text(1001,352,'サポート',13,bold=True)
text(868,396,'優先度',12,C['muted'])
text(1001,396,'通常',13,bold=True)
line(868,438,1145,438)
text(868,458,'関連資料',12,C['muted'],True)
rect((867,482,1147,516),C['canvas'],6)
rect((880,491,892,507),C['white'],2,C['green'])
line(883,496,889,496,C['green'])
line(883,500,889,500,C['green'])
text(902,493,'業務フロー.pdf',12,C['green'],True)
text(1087,495,'256 KB',9,C['muted'])

rect((250,449,824,708),C['white'],12,C['line'])
text(272,472,'対応履歴',16,bold=True)
text(708,477,'社内メモ',12,C['green'],True)
line(271,510,802,510)
line(291,538,291,605,C['line'],2)
rect((284,535,298,549),C['pale'],7)
rect((287,538,295,546),C['green'],4)
text(314,536,'お問い合わせを受け付けました',13,bold=True)
text(314,559,'本日 09:30   ・   受付フォーム',11,C['muted'])
rect((272,592,802,645),C['canvas'],8,C['line'])
text(286,611,'チームに共有するメモを入力…',12,C['muted'])
button(672,656,130,'メモを追加',True)

rect((846,554,1168,708),C['pale'],12)
text(868,577,'次のアクション',14,C['green'],True)
text(868,609,'担当チームを確認して、',13)
text(868,633,'対応を開始しましょう。',13)
text(868,671,'更新内容は履歴に保存されます',10,C['muted'])
save('inquiry-detail.png')

# Separate poster only: the play control is intended as a design affordance,
# not proof that a playable media file has been supplied.
poster=Image.open(OUT/'inquiry-overview.png').convert('RGBA')
overlay=Image.new('RGBA',poster.size,(5,34,27,45))
poster=Image.alpha_composite(poster,overlay)
pd=ImageDraw.Draw(poster)
pd.rounded_rectangle((504,301,696,449),24,fill=(14,57,44,235))
pd.ellipse((566,324,634,392),fill=(255,255,255,245))
pd.polygon([(594,342),(594,374),(617,358)],fill=(21,130,103,255))
f=ImageFont.truetype('C:/Windows/Fonts/YuGothB.ttc',18)
label='操作イメージ'
tw=pd.textlength(label,font=f)
pd.text(((W-tw)/2,414),label,font=f,fill='white',anchor='lt')
poster.convert('RGB').save(OUT/'workflow-poster.png',optimize=True)
print('\n'.join(f'{p.name}: {Image.open(p).size} / {p.stat().st_size:,} bytes' for p in OUT.glob('*.png')))
