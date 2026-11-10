"""Phone-size copies of the broadcast films for the app bundle (ChessGameKiller/Broadcast/Films).
The masters (about 14 MB each, made with fal.ai) and the masks are not in git: they are in the project's
shared files under broadcast-view/. Run from a folder with an out/ directory; needs ffmpeg with libx265,
numpy and Pillow.
King clips: straight transcode to HEVC 1080p. Knight clips: only the knight (and the strip of table his arm crosses)
is kept, the rest is black, so the bytes go where the mask shows; lit variants carry the storm's light baked in."""
import sys,subprocess,json,os,numpy as np
from PIL import Image, ImageFilter
P='/mnt/project-files/broadcast-view/'; S=P+'src/'; OUT='out/'
W,H=1920,1080
X265=['-c:v','libx265','-preset','slow','-crf','27','-tag:v','hvc1','-pix_fmt','yuv420p','-color_primaries','bt709','-color_trc','bt709','-colorspace','bt709','-color_range','tv','-an','-movflags','+faststart','-x265-params','log-level=error:keyint=48']
def king(src,name,frames=120):
    subprocess.run(['ffmpeg','-loglevel','error','-y','-i',P+src+'.mp4','-vf','scale=1920:1080:flags=lanczos,fps=24,setsar=1','-frames:v',str(frames)]+X265+[OUT+f'broadcast-king-{name}.mp4'],check=True)
def read(path):
    p=subprocess.Popen(['ffmpeg','-loglevel','error','-i',path,'-vf','scale=1920:1080:flags=lanczos:in_color_matrix=bt709:in_range=tv,fps=24','-f','rawvideo','-pix_fmt','rgb24','-'],stdout=subprocess.PIPE)
    while True:
        b=p.stdout.read(W*H*3)
        if len(b)<W*H*3: break
        yield np.frombuffer(b,np.uint8).reshape(H,W,3)
def keep(mask):
    m=Image.open(S+mask).convert('L').point(lambda v:255 if v>0 else 0).filter(ImageFilter.MaxFilter(33))
    return (np.asarray(m)>0)[...,None]
KEEP={'tight':'wolf-knight-mask1080.png','wide':'wolf-knight-mask_wide.png','wide2':'wolf-knight-mask_wide2.png'}
def gains(event): return np.array(json.load(open(S+f'event-light-{event}.json'))['gain_rgb'])
def knight(src,name,mask,frames=120,light=None,offset=0,strength=0.85):
    """light: the King's event whose light falls on him; offset: the event's frame at this clip's frame 0 (negative: it starts later)."""
    k=keep(KEEP[mask]); g=gains(light) if light else None
    enc=subprocess.Popen(['ffmpeg','-loglevel','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s','1920x1080','-r','24','-i','-','-vf','scale=out_color_matrix=bt709:out_range=tv']+X265+[OUT+f'broadcast-knight-{name}.mp4'],stdin=subprocess.PIPE)
    for i,f in enumerate(read(P+f'wolf-knight-{src}.mp4')):
        if i>=frames: break
        x=f.astype(np.float32)
        if g is not None:
            j=i+offset
            if 0<=j<len(g):
                # brighter than it was and past the knee: half the excess, so highlights don't clip flat (and a gain of 1 changes nothing)
                y=x*(1+(g[j]-1)*strength); knee=np.maximum(x,200); x=np.where(y>knee,knee+(y-knee)*0.5,y)
        enc.stdin.write((np.clip(x,0,255).astype(np.uint8)*k).tobytes())
    enc.stdin.close(); enc.wait()
EVENT_AT=67  # frames into the knight's strike when the King's storm clip starts (BroadcastScript.stormDelay)
HANDOVER=114 # the strike's frame on screen when the film after it shows its first: started at 112 (BroadcastScript.handover), about two frames to load
JOBS={
 'king-lean':lambda:king('king-lean','lean'),'king-nod':lambda:king('king-nod-kling','nod'),
 'king-near':lambda:king('king-reach-short-v2','near'),'king-far':lambda:king('king-reach-long-v2','far'),
 'king-strike':lambda:king('king-strike','strike'),'king-pleased':lambda:king('king-pleased','pleased'),
 'king-win':lambda:king('king-win','win',121),'king-lose':lambda:king('king-lose','lose',121),
 'king-loss-pawn':lambda:king('king-loss-pawn','loss-pawn'),'king-loss-piece':lambda:king('king-loss-piece','loss-piece'),'king-loss-queen':lambda:king('king-loss-queen','loss-queen'),
 'knight-think':lambda:knight('think','think','tight'),'knight-nod':lambda:knight('nod','nod','tight'),'knight-lean':lambda:knight('lean','lean','tight'),
 'knight-near':lambda:knight('near','near','wide'),'knight-far':lambda:knight('far','far','wide'),'knight-strike':lambda:knight('strike','strike','wide'),
 'knight-pleased':lambda:knight('pleased','pleased','tight'),'knight-win':lambda:knight('win','win','tight',121),
 'knight-lose':lambda:knight('lose','lose','wide2',121,light='king-win'),
}
for e in ['pawn','piece','queen']:
    JOBS[f'knight-strike-{e}']=(lambda e=e:knight('strike',f'strike-{e}','wide',light=f'king-loss-{e}',offset=-EVENT_AT))
    JOBS[f'knight-pleased-{e}']=(lambda e=e:knight('pleased',f'pleased-{e}','tight',light=f'king-loss-{e}',offset=HANDOVER-EVENT_AT))
if __name__=='__main__':
    for j in (sys.argv[1:] or JOBS):
        JOBS[j](); print('done',j,flush=True)
