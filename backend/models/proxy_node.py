from sqlalchemy import Column, Integer, String, Boolean, DateTime, Text
from sqlalchemy.sql import func
from database import Base


class ProxyNode(Base):
    """出口节点（代理/加速器节点记录）

    用途：记录用户可用的出口节点（国家/协议/服务器/订阅），
    注册"切换国家"时用于校验与引导（后端 GeoIP 识别设备当前出口，
    与 device.country 目标比对；节点列表展示该国的可用出口资源）。

    设备真正走不走该节点取决于手机网络层（加速器/VPN App 是否连接），
    本表只做"出口资源台账 + 校验引导"，不做流量转发。
    """
    __tablename__ = "proxy_nodes"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(200), default="")          # 节点名（如"美西-洛杉矶-1"）
    country = Column(String(50), default="", index=True)  # 目标国家（美国/日本/...）
    protocol = Column(String(30), default="")       # wireguard/openvpn/shadowsocks/vless/clash/其他
    address = Column(String(255), default="")       # 服务器地址/IP
    port = Column(Integer, default=0)               # 端口（可空=0）
    config = Column(Text, default="")               # 配置文本/订阅URL/分享链接
    remark = Column(Text, default="")               # 备注
    enabled = Column(Boolean, default=True)         # 是否启用
    api_id = Column(String(20), default="")         # 归属租户（admin 建共享）
    created_at = Column(DateTime(timezone=True), server_default=func.now())
