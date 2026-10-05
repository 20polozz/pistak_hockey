import asyncio, sys, json
from playwright.async_api import async_playwright
# usage: shot.py <steps.json>  steps: [["goto"],["wait",ms],["click",x,y],["shot","name"],["type","text"],["reload"],["offline",true]]
async def main():
    steps = json.load(open(sys.argv[1]))
    async with async_playwright() as p:
        ctx = await p.chromium.launch_persistent_context('.e2e_profile', args=['--no-sandbox','--use-fake-ui-for-media-stream','--use-fake-device-for-media-stream'], permissions=['microphone'], viewport={'width': 412, 'height': 900}, locale='ca-ES')
        b = ctx
        page = await ctx.new_page()
        logs = []
        page.on('console', lambda m: logs.append(f'{m.type}: {m.text}'))
        page.on('pageerror', lambda e: logs.append(f'PAGEERROR: {e}'))
        for s in steps:
            k = s[0]
            if k == 'goto': await page.goto('http://127.0.0.1:8765/', wait_until='load')
            elif k == 'wait': await page.wait_for_timeout(s[1])
            elif k == 'click': await page.mouse.click(s[1], s[2])
            elif k == 'type': await page.keyboard.type(s[1])
            elif k == 'key': await page.keyboard.press(s[1])
            elif k == 'shot': await page.screenshot(path=f'{s[1]}.png')
            elif k == 'reload': await page.reload(wait_until='load')
            elif k == 'offline': await ctx.set_offline(s[1])
            elif k == 'viewport': await page.set_viewport_size({'width': s[1], 'height': s[2]})
            elif k == 'wheel':
                await page.mouse.move(206, 450); await page.mouse.wheel(0, s[1])
            elif k == 'eval': print('EVAL', await page.evaluate(s[1]))
        print('\n'.join(logs[-40:]))
        await b.close()
asyncio.run(main())
