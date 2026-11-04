"""Enumerate ordinary Swift string literals, including nested interpolation expressions."""

def tokens(text):
 result=[]
 def string(i):
  start=i;i+=1
  while i<len(text):
   if text[i]=='\\':
    if i+1<len(text) and text[i+1]=='(':
     i=expr(i+2);continue
    i+=2;continue
   if text[i]=='"':
    result.append((start,i+1,text[start+1:i]));return i+1
   i+=1
  raise ValueError('Unterminated string')
 def expr(i):
  depth=1
  while i<len(text):
   if text.startswith('//',i):i=text.find('\n',i);continue
   if text[i]=='"':i=string(i);continue
   if text[i]=='(':depth+=1
   elif text[i]==')':
    depth-=1
    if depth==0:return i+1
   i+=1
  raise ValueError('Unterminated interpolation')
 i=0
 while i<len(text):
  if text.startswith('//',i):
   end=text.find('\n',i);i=len(text) if end<0 else end;continue
  if text.startswith('/*',i):
   depth=1;i+=2
   while depth and i<len(text):
    if text.startswith('/*',i):depth+=1;i+=2
    elif text.startswith('*/',i):depth-=1;i+=2
    else:i+=1
   continue
  if text[i]=='"':i=string(i)
  else:i+=1
 return result
