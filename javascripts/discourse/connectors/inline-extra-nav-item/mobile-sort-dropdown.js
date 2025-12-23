import Component from "@glimmer/component";
import { service } from "@ember/service";
import { action } from "@ember/object";
import DiscourseURL from "discourse/lib/url";

export default class MobileSortDropdown extends Component {
    @service router;

    get currentURL() {
        return this.router?.currentURL || "";
    }

    get isLatest() {
        const path = this._currentPathNoQuery;
        return path.endsWith("/latest") || path.includes("/l/latest");
    }

    get isTop() {
        const path = this._currentPathNoQuery;
        return path.endsWith("/hot") || path.includes("/l/hot");
    }

    get isCategories() {
        const path = this._currentPathNoQuery;
        return path === "/categories" || path.startsWith("/categories");
    }

    @action
    goTo(path) {
        if (path) {
            DiscourseURL.routeTo(path);
        }
    }

    get currentValue() {
        if (this.isLatest) return "latest";
        if (this.isTop) return "hot";
        if (this.isCategories) return "categories";
        return "latest";
    }

    get dropdownContent() {
        return [
            { id: "latest", name: "最新" },
            { id: "hot", name: "热门" },
            { id: "categories", name: "类别" },
        ];
    }

    @action
    onSelect(item) {
        const id = item?.id ?? item;
        if (id === "latest") return this.goTo(this._buildListPath("latest"));
        if (id === "hot") return this.goTo(this._buildListPath("hot"));
        if (id === "categories") return this.goTo("/categories");
    }

    // Helpers
    get _currentPathNoQuery() {
        const url = this.currentURL || "";
        const q = url.indexOf("?");
        const h = url.indexOf("#");
        let end = url.length;
        if (q !== -1) end = Math.min(end, q);
        if (h !== -1) end = Math.min(end, h);
        return url.slice(0, end);
    }

    _buildListPath(target) {
        const path = this._currentPathNoQuery || "/";

        if (path.startsWith("/c/")) {
            const lIndex = path.indexOf("/l/");
            if (lIndex !== -1) {
                return path.slice(0, lIndex + 3) + target;
            } else {
                return path.replace(/\/$/, "") + "/l/" + target;
            }
        }

        if (path.startsWith("/tag/") || path.startsWith("/tags/")) {
            const lIndex = path.indexOf("/l/");
            if (lIndex !== -1) {
                return path.slice(0, lIndex + 3) + target;
            } else {
                return path.replace(/\/$/, "") + "/l/" + target;
            }
        }

        return "/" + target;
    }
}




