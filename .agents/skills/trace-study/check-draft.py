#!/usr/bin/env python3
"""구간 초안 검사 — 사용자에게 내기 전에 돌린다.

    python3 .agents/skills/trace-study/check-draft.py <초안파일>
    cat draft.md | python3 .agents/skills/trace-study/check-draft.py

왜 스크립트인가: 여기 담긴 것은 전부 **규칙 문서에 이미 있던 것들**인데도 반복해서 어겼다.
2026-08-13 사용자 지적 — "룰즈나 어디 스킬이나 다 적어두면은 뭐해? 텍스트만 늘어봤자."
효과를 본 처방은 텍스트가 아니라 실행되는 절차였다((b-3)·(b-4) 선례).

⚠️ 이 검사가 잡는 것은 **형태**뿐이다. "설명이 이해되는가"는 못 잡는다.
   항목은 사용자가 찾아낼 때마다 늘린다 — 같은 것을 두 번 찾게 하지 않는 것이 목적이다.
"""
import re
import sys

# 소제목이 답이 아니라 예고·질문으로 끝나는 형태 (note-format.md 「소제목은 답을 담는다」)
TITLE_BAD = [
    (r'(까|는가|인가|일까|ㄹ까)\s*[?？]?\s*$', '질문형으로 끝난다 — 답을 제목에 담는다'),
    (r'(이렇게|그렇게|이런|그런)', '가리키기만 한다 — 무엇인지 그 자리에 적는다'),
    (r'(어떻게|어디서|어디에|무엇을|무엇이|언제)[^.]*(나|까|는가|인가|지)\s*[?？]?\s*$',
     '질문을 제목으로 삼았다 — 답을 제목에 담는다'),
    (r'(에 따라 )?(다르다|다릅니다|달라진다|달라집니다)\s*$', '"다르다"는 답이 아니다 — 어떻게 다른지 적는다'),
]

# 문단 첫머리 지시어 (SKILL.md 「줄 번호·지시어로 문장을 열지 않는다」 계열)
LEAD_BAD = re.compile(
    r'^\s*(?:<[^>]+>\s*)*'
    r'(이 |그 |저 |이것|그것|여기|거기|위의|위에서|아래|앞의|앞서|왼쪽|오른쪽|그림)'
)

# 느낌으로 대신 쓴 표현 (SKILL.md 「비유적 어휘로 일반 명사·동사를 대체하지 않는다」)
# 대상을 안 밝힌 지시 명사구 — 2026-08-25 "2번에서 말하는 이 값이 무슨 말인거야?"
DEICTIC = re.compile(r'(?<![가-힣])(이|그|저)\s(값|숫자|표시|줄|칸|부분|조건)')

VAGUE = ['흔들리', '흔들린', '껑충', '묻히', '묻힌', '깜빡', '껑충', '뚝뚝', '널뛰', '쏟아']

# 앞 구간에서 정한 말 — 다시 쓸 때 어디서 정했는지 이어주지 않으면 뜻이 안 잡힌다
# (2026-08-26 사용자 — "쓸만한 점이 우리가 말한 오차를 말하는건가? 앞에 부분이라서 잠깐 까먹었어")
DEFINED_TERMS = {'쓸 만한 점': 'p1s3', '오차 반경': 'p1s3', '예열': 'p1s2',
                 '누적 거리': 'p1s5', '활동 시간': 'p2s'}

# 사용자가 볼 필요 없는 것 (2026-08-26 사용자 요청 — saving.md 「노트가 담는 것은 기능이 어떻게
# 동작하는가뿐」을 기계로 옮긴 것). 노트/백로그/agent-log 중 목적지가 노트가 아닌 것들이다.
OFF_NOTE = [
    (r'(단위 ?테스트|테스트가 |테스트는 |시뮬레이터|GPX|XCTest|드러났습니다|드러났다)',
     '테스트·도구 이야기 — agent-log로'),
    (r'(했을 것|였을 것|일 것이다|았을 것|을 것입니다|아마 |듯하다)',
     '추측 — 재본 것이 아니면 뺀다'),
    (r'(확인했다|확인했습니다|찾아보니|살펴보니|이번에 |뒤져|추적해)',
     '내 작업 이력 — agent-log로'),
    (r'(고쳐야 한다|고쳐야 합니다|개선하면|넣어야 한다|바꿔야 한다|리팩터)',
     '판정·처방 — 백로그로'),
]

# 이력 나열 — 커밋 해시가 여럿이면 「무엇을 왜 정했나」가 아니라 작업 기록이다
# (2026-08-30 사용자 지적 — "굳이 내가 이것을 기능을 위해서 알아야될 필요가 없지 않아?
#  특히 3,4번은 「다 만들었다고 여긴 뒤」 이런것들이 왜 있어야 하는지 모르겠어")
COMMIT_HASH = re.compile(r'`[0-9a-f]{7}`')

# 목표 깊이 표 — 자동 판정이 안 되므로 소제목을 뽑아 되묻는다 (SKILL.md 「목표 깊이」)
DEPTH_OK = ['왜 그렇게 정했나 · 기각한 대안', '무엇을 기준으로 삼았나', '어떤 순서로 이어지나']
DEPTH_NO = ['그 기준을 어떤 계산으로 재나', '무엇을 받아 무엇을 돌려주나']

# 어느 화면인지 안 밝힌 맨 「화면」 — 2026-08-26 사용자 지적
# ("여기서 말하는 화면 보조행이 실제 앱 화면인지 잠금화면인지에 대해서 표현들을 명확하게 해줘")
# 청크 4는 같은 숫자가 러닝 탭 화면과 잠금화면에 따로 뜨므로, 그냥 「화면」이면 어느 쪽인지 안 잡힌다.
# 화면 이름이 이미 나온 문단에서만 재서 "화면에 뜬다" 같은 일반 표현까지 잡지 않는다.
SCREEN_NAMES = ['러닝 탭 화면', '러닝 탭', '잠금화면', '요약 화면', '기록 탭', '기록 상세',
                '대기 화면', '뛰는 중 화면', '코스 탭']
BARE_SCREEN = re.compile(r'(?<![가-힣])화면')

# 그림이 화면 흐름인지 재는 근사 — 화면 상태 이름이 그림 안에 있는가
SCREEN_WORDS = ['대기', '카운트다운', '신호', '뛰는 중', '일시정지', '요약', '기록 탭', '화면']

# 구간 머리에 "언제 일어나는 일인가"가 있는가
WHEN_WORDS = ['뛰는 중', '뛰는 동안', '러닝 내내', '시작', '카운트다운', '종료', '순간',
              '동안', '때마다', '1초에', '매번', '들어올 때', '누르면']


def paragraphs(text):
    """빈 줄로 나뉜 덩어리 중 제목·코드블록·태그줄이 아닌 것."""
    out, buf, in_code = [], [], False
    for line in text.split('\n'):
        if line.strip().startswith('```'):
            in_code = not in_code
            continue
        if in_code:
            continue
        if not line.strip():
            if buf:
                out.append(' '.join(buf))
                buf = []
            continue
        if re.match(r'^\s*(#{1,6}\s|[-*|>]|\d+\.\s)', line):
            if buf:
                out.append(' '.join(buf))
                buf = []
            continue
        buf.append(line.strip())
    if buf:
        out.append(' '.join(buf))
    return out


def titles(text):
    out = []
    for m in re.finditer(r'^\s*#{2,6}\s+(.+?)\s*$', text, re.M):
        out.append(m.group(1))
    for m in re.finditer(r'<(h[2-6])[^>]*>(.*?)</\1>', text, re.S):
        out.append(re.sub(r'<[^>]+>', '', m.group(2)).strip())
    return out


def strip_tags(s):
    return re.sub(r'<[^>]+>', '', s)


def check(text, seg_id=None):
    hits = []

    for t in titles(text):
        plain = strip_tags(t)
        for pat, why in TITLE_BAD:
            if re.search(pat, plain):
                hits.append(('소제목', plain[:60], why))
                break

    paras = html_paragraphs(text) if re.search(r'<p[\s>]', text) else paragraphs(text)
    for p in paras:
        plain = strip_tags(p).strip()
        if not plain:
            continue
        # 인용문은 원문이라 고칠 수 없다 — 어휘 검사에서 뺀다
        outside = re.sub(r'[“”"]|&#82[12][01];', '"', plain)
        outside = re.sub(r'"[^"]*"', '', outside)
        if LEAD_BAD.match(plain):
            hits.append(('문단 첫머리', plain[:50], '지시어·그림 위치로 연다 — 무엇인지 이름으로 부른다'))
        body = re.sub(r'^\s*[📌✅⚠️🔑🎯]\s*\*\*[^*]+\*\*', '', p)
        n = body.count('<strong>') + len(re.findall(r'\*\*[^*]+\*\*', body))
        if n > 2:
            hits.append(('강조', plain[:40], f'굵은 글씨 {n}개 — 문단당 둘까지'))
        for w in VAGUE:
            if w in outside:
                hits.append(('느낌 표현', w, '실제로 무슨 일이 일어나는지로 쓴다'))
                break
        m = DEICTIC.search(outside)
        if m:
            hits.append(('지시 명사구', m.group(0), '무엇의 것인지 그 자리에 이름으로 적는다'))
        for pat, why in OFF_NOTE:
            mm = re.search(pat, outside)
            if mm:
                hits.append(('볼 필요 없는 것', mm.group(0), why))
                break
        if any(nm in outside for nm in SCREEN_NAMES):
            rest = outside
            for nm in SCREEN_NAMES:
                rest = rest.replace(nm, '')
            if BARE_SCREEN.search(rest):
                hits.append(('어느 화면인지', plain[:40],
                             '화면이 여럿인 문단이다 — 그냥 「화면」이면 어느 쪽인지 안 잡힌다'))

    for term, home in DEFINED_TERMS.items():
        if seg_id and seg_id.startswith(home):
            continue
        if term in text and not re.search(re.escape(term) + r'[\s\S]{0,60}(구간 (?:[①-⑩]|&#93[12]\d;)|파트 \d)', text):
            if not re.search(r'(구간 (?:[①-⑩]|&#93[12]\d;)|파트 \d)[\s\S]{0,60}' + re.escape(term), text):
                hits.append(('앞에서 정한 말', term,
                             '어디서 정한 말인지 이어준다 — 한 구간만 열어 보면 뜻이 안 잡힌다'))

    figs = re.findall(r'```.*?```', text, re.S) + re.findall(r'<svg.*?</svg>', text, re.S)
    hashes = COMMIT_HASH.findall(text)
    if len(hashes) >= 3:
        hits.append(('이력 나열', ' '.join(hashes[:4]),
                     '커밋을 늘어놓으면 작업 기록이다 — 남길 것은 「무엇이 왜 그렇게 정해졌나」 한 줄'))

    if figs:
        for f in figs:
            if not any(w in f for w in SCREEN_WORDS):
                hits.append(('그림', f.strip()[:40].replace('\n', ' '),
                             '화면 상태가 없다 — 코드 분기도가 아니라 화면 흐름 위에 얹는다'))
    else:
        hits.append(('그림', '(없음)', '흐름이 있는 설명이면 그림을 먼저 놓는다'))

    # 값이 흘러가는 그림이 하나는 있는가 — 2026-08-30 사용자 지적
    # ("이 상황이 실제로 어떻게 이루어지고 그 안에서 계산이 어떻게 되는지를 이해하지 못하고 있는데")
    # 값 하나만 있으면 상태이지 변화가 아니다. 숫자 셋 + 이어주는 기호를 근사로 쓴다.
    if figs and not any(
        len(re.findall(r'\d+(?:\.\d+)?', f)) >= 3 and any(c in f for c in '→↓─╱╲')
        for f in figs
    ):
        hits.append(('값 흐름', f'그림 {len(figs)}개',
                     '그 순간에 값이 어떻게 움직이는지를 숫자로 따라가는 그림이 없다'))

    # 그림이 구간 머리에만 몰리는 것 — 2026-08-26 사용자 지적
    # ("맨 처음 부분만 그렇게 하는데 중간 부분에 대해서도 시각적으로 표현하면 더 좋을 것들이 훨씬 많다")
    # ⚠️ 무조건 넣으라는 뜻이 아니다 — 사용자가 그날 바로 좁혔다:
    #   "특정 시나리오 및 흐름에 대해서 설명하는 구간이면 넣으라고 한거였는데".
    #   값 하나의 정의·선언만 있는 소제목은 그림 없이 넘어가는 것이 맞다.
    subheads = len(re.findall(r'<h4[\s>]', text)) or len(re.findall(r'^###\s', text, re.M))
    if subheads >= 3 and len(figs) <= 1:
        hits.append(('그림 배치', f'소제목 {subheads}개에 그림 {len(figs)}개',
                     '머리에만 몰렸다 — 시나리오·흐름을 설명하는 소제목이 있으면 거기에도 붙인다'))

    head = re.search(r'(📌[^\n]*(?:\n(?!\n)[^\n]*)*)', text)
    if head is None:
        head = re.search(r'<div class="segintro">(.*?)</div>', text, re.S)
    if head is None:
        hits.append(('구간 머리', '(없음)', '「이 구간이 다루는 것」이 없다'))
    elif not any(w in strip_tags(head.group(1)) for w in WHEN_WORDS):
        hits.append(('구간 머리', strip_tags(head.group(1))[:50],
                     '「언제 일어나는 일인가」가 없다 — 러닝의 어느 시점인지 한 줄 넣는다'))

    # 구간 머리가 코드 동작이 아니라 사용자 장면으로 열리는가 — 2026-08-26 사용자 요청
    # ("유저 입장에서해야 해당 화면과 기능 흐름이 자연스럽잖아 … 다른 설명에도 반영을 해줬으면")
    if head is not None:
        htext = strip_tags(head.group(1))
        if not any(w in htext for w in SCREEN_WORDS + ['버튼', '누르', '탭', '보인다', '뜬다', '장면']):
            hits.append(('구간 머리', htext[:50],
                         '사용자 장면이 없다 — 어느 화면에서 무엇을 하는 순간인지로 연다'))

    return hits


def _strip_note_chrome(html):
    html = re.sub(r'<desc.*?</desc>', '', html, flags=re.S)
    html = re.sub(r'<title.*?</title>', '', html, flags=re.S)
    html = re.sub(r'<figcaption.*?</figcaption>', '', html, flags=re.S)

    html = re.sub(r'<span class="tag">.*?</span>', '', html, flags=re.S)
    return html


def html_paragraphs(html):
    """HTML 노트에서 <p>·<li> 본문만 뽑는다 (markdown 문단 추출이 HTML에서는 부정확하다)."""
    return [strip_tags(m) for m in re.findall(r'<(?:p|li)(?=[\s>])[^>]*>(.*?)</(?:p|li)>', html, re.S)]


def check_note_by_segment(path):
    """노트 전체를 구간 단위로 갈라 하나씩 검사한다 — advisor가 뒤쪽에 치우치는 것을 막는 자리.
    2026-08-26 사용자 요청: "파트 전체를 평등하게 확인을 해주고"."""
    html = _strip_note_chrome(open(path, encoding='utf-8').read())
    segs = re.findall(r'<details class="seg" id="(p\d+s\d+)"[^>]*>(.*?)\n      </details>', html, re.S)
    if not segs:
        print('구간을 찾지 못했다 — 파일 경로를 확인한다')
        return 1

    # 구간 밖도 본다 — 소개 절 · 파트 골격 · 3분 복습 (2026-08-30 `(d)`에서 사각지대로 드러났다.
    # 소개 절을 그날 세 번 고쳤는데 어떤 검사도 안 지나갔다.)
    outside = [(f'소개 {sid}', body) for sid, body
               in re.findall(r'<section id="(\w+)">(.*?)</section>', html, re.S)]
    outside += [(f'골격 {pid}', body) for pid, body
                in re.findall(r'<details class="part" id="(p\d+)"[^>]*>(.*?)<details class="seg"', html, re.S)]
    outside += [('3분 복습', m) for m in re.findall(r'<div class="recap"[^>]*>(.*?)</ol>', html, re.S)]

    total = 0
    for name, body in outside:
        hits = check(body)
        # 구간용 검사는 여기 안 걸린다 — 그림도 구간 머리도 없는 자리다
        skip = {'그림', '그림 배치', '구간 머리'}
        # 3분 복습은 파트를 가로지르는 요약이라 「앞에서 정한 말」이 구조적으로 걸린다
        if name == '3분 복습':
            skip.add('앞에서 정한 말')
        hits = [h for h in hits if h[0] not in skip]
        print(f'── {name}')
        if not hits:
            print('   통과\n')
            continue
        total += len(hits)
        for kind, what, why in hits:
            print(f'   [{kind}] {what[:52]}')
            print(f'       → {why}')
        print()

    for sid, body in segs:
        title = re.search(r'<summary>(.*?)</summary>', body, re.S)
        name = strip_tags(title.group(1)).strip() if title else sid
        hits = check(body, seg_id=sid)
        # 구간 하나만 떼면 그림이 없는 구간도 있으므로 '(없음)'은 빼고 본다
        hits = [h for h in hits if not (h[0] == '그림' and h[1] == '(없음)')]
        print(f'── {sid}  {name}')
        depth_prompt(body, label=f' {sid}')
        if not hits:
            print('   통과\n')
            continue
        total += len(hits)
        for kind, what, why in hits:
            print(f'   [{kind}] {what[:52]}')
            print(f'       → {why}')
        print()
    print(f'합계 {total}건')
    return 1 if total else 0


def depth_prompt(text, label=''):
    """소제목을 뽑아 목표 깊이 표와 함께 되묻는다 — 자동 판정은 하지 않는다.

    왜 출력만 하나: 「이 소제목이 목표 깊이 안인가」는 단어로 인코딩할 수 없다.
    그런데 기준(SKILL.md 「목표 깊이」)은 있는데도 매번 안 재서 절이 쌓였다.
    그래서 판정은 사람이 하되 **빠뜨릴 수는 없게** 눈앞에 편다.
    """
    heads = re.findall(r'^###\s+(.+?)\s*$', text, re.M) or \
            [strip_tags(h) for h in re.findall(r'<h4[^>]*>(.*?)</h4>', text, re.S)]
    if not heads:
        return
    print(f'── 깊이 점검{label} — 자동 판정 없음, 소제목마다 직접 답한다')
    print('   ✅ ' + ' / '.join(DEPTH_OK))
    print('   ❌ ' + ' / '.join(DEPTH_NO))
    for h in heads:
        print(f'   · {h.strip()[:70]}')
    print('   → 각 소제목이 ✅ 셋 중 어디인가. ❌에 걸리면 뺀다.')
    print('   → 이 절이 없어도 능력 선언에 답할 수 있으면 뺀다.\n')


def main():
    if len(sys.argv) > 2 and sys.argv[1] == '--note':
        return check_note_by_segment(sys.argv[2])
    text = open(sys.argv[1], encoding='utf-8').read() if len(sys.argv) > 1 else sys.stdin.read()
    depth_prompt(text)
    hits = check(text)
    if not hits:
        print('통과 — 걸린 것 없음')
        return 0
    print(f'{len(hits)}건 걸림\n')
    for kind, what, why in hits:
        print(f'  [{kind}] {what}')
        print(f'      → {why}\n')
    return 1


if __name__ == '__main__':
    sys.exit(main())
