from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os
F='assets/fonts/'
OUT='assets/tex/signs/'
signs = {
 'bakkal': ('YILDIZ BAKKAL', '#1d4fa8', '#ffffff', 'RussoOne-Regular.ttf'),
 'firin': ('ÖZTÜRK FIRINI', '#b8321f', '#ffe9a8', 'RussoOne-Regular.ttf'),
 'cay': ('ÇAY OCAĞI', '#2f6b2f', '#ffffff', 'RussoOne-Regular.ttf'),
 'berber': ('BERBER HASAN', '#222222', '#e8c35a', 'Rajdhani-Bold.ttf'),
 'eczane': ('ECZANE', '#d0182a', '#ffffff', 'RussoOne-Regular.ttf'),
 'lokanta': ('EMEK LOKANTASI', '#7a1d12', '#f6d27a', 'Rajdhani-Bold.ttf'),
 'kasap': ('KASAP ALİ', '#a31515', '#ffffff', 'RussoOne-Regular.ttf'),
 'market': ('KARDELEN MARKET', '#f2b705', '#1a1a1a', 'RussoOne-Regular.ttf'),
 'kuafor': ('KUAFÖR SELİN', '#7b2d8e', '#ffffff', 'Rajdhani-Bold.ttf'),
 'tekel': ('TEKEL BAYİ', '#0c6b8a', '#ffffff', 'RussoOne-Regular.ttf'),
 'lokum': ('SAFRAN LOKUMCUSU', '#5b2a0f', '#f5c542', 'Rajdhani-Bold.ttf'),
 'bakir': ('BAKIRCILAR ÇARŞISI', '#3b2414', '#e8b26a', 'Rajdhani-Bold.ttf'),
 'han': ('CİNCİ HAN', '#2b2b2b', '#e8d3a2', 'Rajdhani-Bold.ttf'),
 'kahve': ('KAHVEHANE', '#4a2c17', '#f1d9b0', 'Rajdhani-Bold.ttf'),
 'liman': ('SOKAK LİMAN İŞLETMESİ', '#123c66', '#ffffff', 'RussoOne-Regular.ttf'),
 'depo': ('DEPO 7', '#c7a008', '#111111', 'RussoOne-Regular.ttf'),
 'gemi': ('MARMARA YILDIZI', '#ffffff', '#0c2340', 'RussoOne-Regular.ttf'),
 'dikkat': ('DİKKAT! FORKLİFT ÇIKABİLİR', '#f2c200', '#111111', 'Rajdhani-Bold.ttf'),
}
for k,(t,bg,fg,font) in signs.items():
    W,H=1024,192
    im=Image.new('RGB',(W,H),bg)
    d=ImageDraw.Draw(im)
    for y in range(H):
        a=int(30*(y/H)); d.line([(0,y),(W,y)],fill=tuple(max(0,c-a) for c in Image.new('RGB',(1,1),bg).getpixel((0,0))))
    d.rectangle([8,8,W-9,H-9],outline=fg,width=6)
    size=120
    while True:
        f=ImageFont.truetype(F+font,size)
        bb=d.textbbox((0,0),t,font=f)
        if bb[2]-bb[0]<W-80 or size<40: break
        size-=4
    w=bb[2]-bb[0]; h=bb[3]-bb[1]
    sh=Image.new('RGBA',(W,H),(0,0,0,0)); ds=ImageDraw.Draw(sh)
    ds.text(((W-w)/2-bb[0]+4,(H-h)/2-bb[1]+6),t,font=f,fill=(0,0,0,140))
    sh=sh.filter(ImageFilter.GaussianBlur(4)); im.paste(sh,(0,0),sh)
    d.text(((W-w)/2-bb[0],(H-h)/2-bb[1]),t,font=f,fill=fg)
    im.save(OUT+k+'.png')
print('signs', len(signs))
