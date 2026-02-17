from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from motor.motor_asyncio import AsyncIOMotorClient
from beanie import init_beanie
from app.routers import authentications, hold_polygons, share, well_known
from app.models.open_id_nonce import OpenIdNonce as OpenIdNonceModel
from app.models.user import User as UserModel
from app.models.hold_polygon import HoldPolygon as HoldPolygonModel
from app.models.image import Image as ImageModel
from app.models.route import Route as RouteModel
from contextlib import asynccontextmanager
from logging import info
from app.routers import images
from app.routers import routes
from app.routers import users
from app.core.config import get


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    app.mongodb_client = AsyncIOMotorClient(get("mongodb.url"), tz_aware=True)
    app.database = app.mongodb_client.get_database(get("mongodb.name"))
    await init_beanie(
        database=app.database,
        document_models=[OpenIdNonceModel, UserModel, HoldPolygonModel, ImageModel, RouteModel],
    )
    ping_response = await app.database.command("ping")
    if int(ping_response["ok"]) != 1:
        raise Exception("Problem connecting to database cluster.")
    else:
        info("Connected to database cluster.")

    yield
    # Shutdown
    app.mongodb_client.close()


app = FastAPI(lifespan=lifespan)


app.include_router(authentications.router)
app.include_router(hold_polygons.router)
app.include_router(images.router)
app.include_router(routes.router)
app.include_router(users.router)
app.include_router(share.router)
app.include_router(well_known.router)
app.mount("/static", StaticFiles(directory="app/static", html=True), name="static")


if __name__ == "__main__":
    import asyncio
    import uvicorn

    loop = asyncio.get_event_loop()
    config = uvicorn.Config(app=app, port=8080, loop=loop)
    server = uvicorn.Server(config)
    loop.run_until_complete(server.serve())
