from fastapi import FastAPI
from app.routers import hold_polygons


app = FastAPI()


app.include_router(hold_polygons.router)


if __name__ == "__main__":
    import asyncio
    import uvicorn

    loop = asyncio.get_event_loop()
    config = uvicorn.Config(app=app, port=8080, loop=loop)
    server = uvicorn.Server(config)
    loop.run_until_complete(server.serve())
