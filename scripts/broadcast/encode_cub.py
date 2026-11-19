"""Phone-size copies of the Cub's forest films for the app bundle (ChessGameKiller/Broadcast/Films).
The masters (made with fal.ai, Kling v3 pro, 2026-11-15 to 2026-11-19) are not in git: they are in the
project's shared files under cub-hall/. Needs ffmpeg with libx265, numpy and Pillow.
Usage: python3 encode_cub.py OUT_DIR [job ...]

The forest is one painted scene with both players in it: the Wolf Knight on the left, the Cub on the right.
The Cub's films are the whole picture; the knight's are laid over them, cut to the left of the board's middle
(SPLIT, feathered), and kept black outside that, so the bytes go where the mask shows. Every film was made
with the other player holding still, so the two never meet."""
import sys,subprocess,os,numpy as np
from PIL import Image
P='/mnt/project-files/cub-hall/'
W,H=1920,1080
# Where the knight's half ends: his hand never comes right of x=880, the Cub's never left of x=950
# (measured on every film).
SPLIT,FEATHER=915,24
X265=['-c:v','libx265','-preset','slow','-crf','27','-tag:v','hvc1','-pix_fmt','yuv420p','-color_primaries','bt709','-color_trc','bt709','-colorspace','bt709','-color_range','tv','-an','-movflags','+faststart','-x265-params','log-level=error:keyint=48']
SCALE='scale=1920:1080:flags=lanczos,fps=24,setsar=1'
def cub(src,name,frames=120):
    subprocess.run(['ffmpeg','-loglevel','error','-y','-i',P+src+'.mp4','-vf',SCALE,'-frames:v',str(frames)]+X265+[OUT+f'broadcast-cub-{name}.mp4'],check=True)
def ramp():
    x=np.arange(W,dtype=np.float32)
    return np.clip((SPLIT+FEATHER-x)/(2*FEATHER),0,1)
def mask():
    a=(np.tile(ramp(),(H,1))*255).astype(np.uint8)
    img=Image.new('RGBA',(W,H),(255,255,255,0)); img.putalpha(Image.fromarray(a))
    img.resize((W//2,H//2),Image.BICUBIC).save(OUT+'broadcast-cub-knight-mask.png',optimize=True)
def read(path):
    p=subprocess.Popen(['ffmpeg','-loglevel','error','-i',path,'-vf','scale=1920:1080:flags=lanczos:in_color_matrix=bt709:in_range=tv,fps=24','-f','rawvideo','-pix_fmt','rgb24','-'],stdout=subprocess.PIPE)
    while True:
        b=p.stdout.read(W*H*3)
        if len(b)<W*H*3: break
        yield np.frombuffer(b,np.uint8).reshape(H,W,3)
def knight(src,name,frames=120):
    keep=np.zeros(W,bool); keep[:SPLIT+FEATHER+32]=True; keep=keep[None,:,None]
    enc=subprocess.Popen(['ffmpeg','-loglevel','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r','24','-i','-','-vf','scale=out_color_matrix=bt709:out_range=tv']+X265+[OUT+f'broadcast-cub-knight-{name}.mp4'],stdin=subprocess.PIPE)
    for i,f in enumerate(read(P+src+'.mp4')):
        if i>=frames: break
        enc.stdin.write((f*keep).tobytes())
    enc.stdin.close(); enc.wait()
def plate():
    # The still is the films' own first frame, so nothing shifts when the first film fades in over it.
    subprocess.run(['ffmpeg','-loglevel','error','-y','-i',P+'cub-lean-take1.mp4','-vf',SCALE,'-frames:v','1','-q:v','3',OUT+'broadcast-cub-plate.jpg'],check=True)
JOBS={
 'plate':plate,'mask':mask,
 # The whole forest breathing (fog, leaves, owls, the horse at its hay): ten seconds.
 'cub-think':lambda:cub('cub-forest-hay-take1','think',240),
 'cub-lean':lambda:cub('cub-lean-take1','lean'),'cub-nod':lambda:cub('cub-nod-take1','nod'),
 'cub-near':lambda:cub('cub-reach-near-take1','near'),'cub-far':lambda:cub('cub-far-take1','far'),
 'cub-strike':lambda:cub('cub-strike-take1','strike'),'cub-pleased':lambda:cub('cub-pleased-take1','pleased'),
 'cub-upset':lambda:cub('cub-upset-take1','upset'),
 'cub-win':lambda:cub('cub-win-take1','win',121),'cub-lose':lambda:cub('cub-lose-take1','lose',121),
 'knight-think':lambda:knight('cub-forest-hay-take1','think',240),
 'knight-lean':lambda:knight('wk-lean-take1','lean'),'knight-nod':lambda:knight('wk-nod-take2','nod'),
 'knight-near':lambda:knight('wk-near-take2','near'),'knight-far':lambda:knight('wk-far-take1','far'),
 # His own hard move failed three takes (pieces lifted, stretched or vanished): his long reach stands in.
 'knight-strike':lambda:knight('wk-far-take1','strike'),
 'knight-pleased':lambda:knight('wk-pleased-take1','pleased'),'knight-wince':lambda:knight('wk-wince-take1','wince'),
}
if __name__=='__main__':
    OUT=sys.argv[1].rstrip('/')+'/'
    os.makedirs(OUT,exist_ok=True)
    for j in (sys.argv[2:] or JOBS):
        JOBS[j](); print('done',j,flush=True)
